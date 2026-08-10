import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "crypto";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import {
  CloseSharedTaskDto,
  CreateSharedTaskDto,
  SharedTaskListQuery,
  UpdateSharedTaskDto,
} from "../dto/shared-task.dto";
import { SharedTaskRepository } from "./shared-task.repository";
import {
  ResolvedSharedTaskRow,
  SharedTaskRow,
  TaskCloseRow,
} from "./shared-task.types";
import { isTaskOverdue } from "./task-due-state";

interface MutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

interface TaskResultRef extends Record<string, unknown> {
  taskId: string;
  taskVersion: number;
}

export interface CloseResultRef extends TaskResultRef {
  closeId: string;
  closedAt: string;
  closedBy: string;
  closeRequestId: string;
}

const aggregateType = "workflow:shared-task";

@Injectable()
export class SharedTaskService {
  constructor(
    private readonly repository: SharedTaskRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly realtime: RealtimeBus,
  ) {}

  async create(
    actor: ActorContext,
    dto: CreateSharedTaskDto,
    metadata: MutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    const values = await this.validate(dto);
    const taskId = this.deterministicId(
      `${actor.userId}\0workflow.shared-task.create\0${metadata.idempotencyKey}`,
    );
    await this.integrity.executeVersionedMutation<TaskResultRef>({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "workflow.shared-task.create",
      idempotencyKey: metadata.idempotencyKey,
      requestId: metadata.requestId,
      aggregateType,
      aggregateId: taskId,
      expectedVersion: 0,
      payload: values,
      audit: {
        action: "workflow.shared_task_created",
        entityType: "shared_task",
        entityId: taskId,
        afterRef: { taskId, state: "open" },
      },
      outbox: {
        type: "workflow.task.changed",
        payload: { taskId, action: "created" },
      },
      mutate: async (client, version) => {
        await this.repository.create(client, {
          id: taskId,
          ...values,
          version,
          createdBy: actor.userId,
        });
        await this.repository.replaceAudiences(
          client,
          taskId,
          values.audiences,
        );
        await this.repository.replaceReminders(
          client,
          taskId,
          values.reminders,
        );
        return { taskId, taskVersion: version };
      },
    });
    this.realtime.emitCrmChanged({
      entity: "task",
      action: "created",
      id: taskId,
    });
    return this.loadWithAudiencePreview(taskId);
  }

  async update(
    actor: ActorContext,
    taskId: string,
    dto: UpdateSharedTaskDto,
    metadata: MutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    const current = await this.loadRow(taskId);
    if (current.state !== "open") {
      throw new ConflictException({
        code: "TASK_ALREADY_CLOSED",
        message: "Закрытую задачу изменить нельзя.",
      });
    }
    const values = await this.validate(dto);
    await this.integrity.executeVersionedMutation<TaskResultRef>({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "workflow.shared-task.update",
      idempotencyKey: metadata.idempotencyKey,
      requestId: metadata.requestId,
      aggregateType,
      aggregateId: taskId,
      expectedVersion: dto.expectedVersion,
      payload: values,
      audit: {
        action: "workflow.shared_task_updated",
        entityType: "shared_task",
        entityId: taskId,
        beforeRef: this.auditRef(current),
      },
      outbox: {
        type: "workflow.task.changed",
        payload: { taskId, action: "updated" },
      },
      mutate: async (client, version) => {
        const locked = (await this.repository.lock(client, taskId)).rows[0];
        if (!locked) throw new NotFoundException("Задача не найдена.");
        const updated = await this.repository.update(client, taskId, {
          ...values,
          version,
        });
        if (!updated.rows[0]) {
          throw new ConflictException("Задача уже закрыта.");
        }
        await this.repository.replaceAudiences(
          client,
          taskId,
          values.audiences,
        );
        await this.repository.replaceReminders(
          client,
          taskId,
          values.reminders,
        );
        return { taskId, taskVersion: version };
      },
    });
    this.realtime.emitCrmChanged({
      entity: "task",
      action: "updated",
      id: taskId,
    });
    return this.loadWithAudiencePreview(taskId);
  }

  async list(actor: ActorContext, query: SharedTaskListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    if (
      (query.linkedEntityType == null) !== (query.linkedEntityId == null)
    ) {
      this.invalid(
        "linkedEntity",
        "Тип и идентификатор связанного объекта обязательны вместе.",
      );
    }
    const result = await this.repository.listResolved(actor.userId, actor.role, {
      state: query.state,
      // ponytail: one bounded school work queue; add a cursor if it exceeds 2k.
      limit: query.limit ?? 2000,
      taskId: query.taskId,
      linkedEntityType: query.linkedEntityType,
      linkedEntityId: query.linkedEntityId,
      q: query.q?.trim() || undefined,
      priority: query.priority,
      scope: query.scope,
      from: query.from,
      to: query.to,
    });
    await this.repository.recordListResolutions(result.rows, actor.userId);
    const items = await this.toDtos(result.rows);
    return {
      items,
      counters: await this.repository.counters(actor.userId, actor.role, {
        q: query.q?.trim() || undefined,
        priority: query.priority,
        scope: query.scope,
        from: query.from,
        to: query.to,
      }),
    };
  }

  async calendar(actor: ActorContext, query: SharedTaskListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    if (!query.from || !query.to) {
      this.invalid("range", "Для календаря обязательны начало и конец периода.");
    }
    const from = new Date(query.from);
    const to = new Date(query.to);
    if (to <= from || to.getTime() - from.getTime() > 370 * 86_400_000) {
      this.invalid("range", "Период календаря должен быть не больше года.");
    }
    const rows = (
      await this.repository.listResolved(actor.userId, actor.role, {
        state: query.state,
        limit: 2_147_483_647,
        linkedEntityType: query.linkedEntityType,
        linkedEntityId: query.linkedEntityId,
        q: query.q?.trim() || undefined,
        priority: query.priority,
        scope: query.scope,
        from: query.from,
        to: query.to,
      })
    ).rows;
    const formatDay = new Intl.DateTimeFormat("sv-SE", {
      timeZone: "Europe/Moscow",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    const counts = new Map<string, number>();
    for (const row of rows) {
      if (!row.start_at) continue;
      const day = formatDay.format(new Date(row.start_at));
      counts.set(day, (counts.get(day) ?? 0) + 1);
    }
    return {
      items: [...counts.entries()]
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([day, count]) => ({ day, count })),
    };
  }

  async history(actor: ActorContext, taskId: string) {
    const task = await this.resolve(actor, taskId);
    const result = await this.repository.history(task.id);
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        action: row.action,
        actorUserId: row.actor_user_id,
        actorName: [row.actor_first_name, row.actor_last_name]
          .filter(Boolean)
          .join(" ") || null,
        before: row.before_ref,
        after: row.after_ref,
        occurredAt:
          row.created_at instanceof Date
            ? row.created_at.toISOString()
            : row.created_at,
      })),
    };
  }

  async previewAudience(
    actor: ActorContext,
    audiences: CreateSharedTaskDto["audiences"],
  ) {
    this.policy.assertCanWriteCrm(actor);
    await this.validateAudiences(audiences);
    return this.buildAudiencePreview(audiences);
  }

  async close(
    actor: ActorContext,
    taskId: string,
    dto: CloseSharedTaskDto,
    metadata: MutationMetadata,
  ) {
    this.policy.assertCanReadOperationalData(actor);
    this.assertMetadata(metadata);
    const scoped = await this.resolve(actor, taskId);
    if (scoped.closed_at) return this.closeDto(scoped);
    const affectedUserIds = (
      await this.repository.reminderRecipients(taskId)
    ).rows.map((row) => row.user_id);

    try {
      const result =
        await this.integrity.executeVersionedMutation<CloseResultRef>({
          actorKey: actor.userId,
          actorUserId: actor.userId,
          operation: "workflow.shared-task.close",
          idempotencyKey: metadata.idempotencyKey,
          requestId: metadata.requestId,
          aggregateType,
          aggregateId: taskId,
          expectedVersion: dto.expectedVersion,
          payload: { taskId },
          audit: {
            action: "workflow.shared_task_closed",
            entityType: "shared_task",
            entityId: taskId,
            beforeRef: { taskId, state: "open", version: dto.expectedVersion },
          },
          outbox: {
            type: "workflow.task.closed",
            payload: { taskId },
          },
          mutate: async (client, version) => {
            const current = (await this.repository.lock(client, taskId)).rows[0];
            if (!current) throw new NotFoundException("Задача не найдена.");
            const close = (
              await this.repository.close(
                client,
                taskId,
                actor.userId,
                metadata.requestId,
              )
            ).rows[0]!;
            await client.query(
              `
                update app.shared_tasks
                set state = 'closed', version = $2, updated_at = now()
                where id = $1
              `,
              [taskId, version],
            );
            await this.repository.recordResolution(
              client,
              scoped,
              "close",
              actor.userId,
              metadata.requestId,
            );
            await this.repository.cancelPendingReminders(client, taskId);
            return this.closeRef(taskId, version, close);
          },
        });
      this.realtime.emitCrmChanged({
        entity: "task",
        action: "deleted",
        id: taskId,
        affectedUserIds,
      });
      return result.resultRef;
    } catch (error) {
      if (!this.isStaleVersion(error)) throw error;
      const resolved = await this.resolve(actor, taskId);
      if (!resolved.closed_at) throw error;
      return this.closeDto(resolved);
    }
  }

  private async validate(dto: CreateSharedTaskDto) {
    const title = dto.title.trim();
    if (!title) this.invalid("title", "Заголовок обязателен.");
    const start = new Date(dto.startAt);
    const end = dto.endAt ? new Date(dto.endAt) : null;
    if (dto.allDay && end) {
      this.invalid("endAt", "У задачи на весь день нет времени окончания.");
    }
    if (!dto.allDay && (!end || end <= start)) {
      this.invalid("endAt", "Окончание должно быть позже начала.");
    }
    await this.validateAudiences(dto.audiences);
    if (
      dto.linkedEntity &&
      !(await this.repository.entityExists(
        dto.linkedEntity.type,
        dto.linkedEntity.id,
      ))
    ) {
      this.invalid("linkedEntity", "Связанная запись не найдена.");
    }
    const reminders = dto.reminders ?? [];
    const reminderKeys = new Set<string>();
    for (const reminder of reminders) {
      const dueAt = new Date(reminder.dueAt);
      if (Number.isNaN(dueAt.getTime())) {
        this.invalid("reminders", "Некорректное время напоминания.");
      }
      const key = `${dueAt.toISOString()}:${reminder.channel}`;
      if (reminderKeys.has(key)) {
        this.invalid("reminders", "Напоминание не должно повторяться.");
      }
      reminderKeys.add(key);
    }
    return {
      title,
      body: dto.body?.trim() || null,
      allDay: dto.allDay,
      priority: dto.priority ?? "medium",
      startAt: start.toISOString(),
      endAt: end?.toISOString() ?? null,
      linkedEntityType: dto.linkedEntity?.type ?? null,
      linkedEntityId: dto.linkedEntity?.id ?? null,
      audiences: dto.audiences.map((audience) => ({
        type: audience.type,
        ...(audience.targetId ? { targetId: audience.targetId } : {}),
      })),
      reminders: reminders.map((reminder) => ({
        dueAt: new Date(reminder.dueAt).toISOString(),
        channel: reminder.channel,
      })),
    };
  }

  private async validateAudiences(
    audiences: CreateSharedTaskDto["audiences"],
  ) {
    const seen = new Set<string>();
    for (const audience of audiences) {
      if (
        audience.type === "allBranches" &&
        audience.targetId !== undefined
      ) {
        this.invalid(
          "audiences",
          "Для всей школы идентификатор филиала не используется.",
        );
      }
      const key = `${audience.type}:${audience.targetId ?? ""}`;
      if (seen.has(key)) {
        this.invalid("audiences", "Получатель не должен повторяться.");
      }
      seen.add(key);
      if (
        !(await this.repository.audienceTargetExists(
          audience.type,
          audience.targetId,
        ))
      ) {
        this.invalid("audiences", "Получатель не найден или недоступен.");
      }
    }
  }

  private async loadWithAudiencePreview(taskId: string) {
    const task = await this.load(taskId);
    return {
      ...task,
      recipientSummary: await this.buildAudiencePreview(task.audiences),
    };
  }

  private async buildAudiencePreview(
    audiences: CreateSharedTaskDto["audiences"],
  ) {
    const rows = (await this.repository.previewAudienceRecipients(audiences)).rows;
    const selectors = audiences.map((audience, index) => {
      const matches = rows.filter(
        (row) => row.selector_index === index && row.user_id != null,
      );
      const row = rows.find((item) => item.selector_index === index);
      return {
        type: audience.type,
        ...(audience.targetId ? { targetId: audience.targetId } : {}),
        label: row?.selector_label ??
          (audience.type === "allBranches" ? "Вся школа" : "Получатель"),
        mode: audience.type === "user" ? "fixed" : "dynamic",
        currentRecipientCount: new Set(matches.map((item) => item.user_id)).size,
      };
    });
    const recipients = new Map<
      string,
      { userId: string; name: string; role: string | null }
    >();
    for (const row of rows) {
      if (!row.user_id || recipients.has(row.user_id)) continue;
      recipients.set(row.user_id, {
        userId: row.user_id,
        name:
          [row.first_name, row.last_name].filter(Boolean).join(" ") ||
          row.email ||
          "Сотрудник",
        role: row.role,
      });
    }
    return {
      totalRecipients: recipients.size,
      hasDynamicMembership: audiences.some((item) => item.type !== "user"),
      selectors,
      recipients: [...recipients.values()],
    };
  }

  private async resolve(actor: ActorContext, taskId: string) {
    const row = (
      await this.repository.resolved(actor.userId, actor.role, taskId)
    ).rows[0];
    if (!row) throw new NotFoundException("Задача не найдена.");
    return row;
  }

  private async load(taskId: string) {
    return this.toDto(await this.loadRow(taskId));
  }

  private async loadRow(taskId: string) {
    const row = (await this.repository.find(taskId)).rows[0];
    if (!row) throw new NotFoundException("Задача не найдена.");
    return row;
  }

  private async toDto(row: SharedTaskRow | ResolvedSharedTaskRow) {
    const [audiences, reminders] = await Promise.all([
      this.repository.audienceProjection(row.id),
      this.repository.reminderProjection(row.id),
    ]);
    return this.buildDto(row, audiences.rows, reminders.rows);
  }

  private async toDtos(rows: readonly ResolvedSharedTaskRow[]) {
    const ids = rows.map((row) => row.id);
    const [audiences, reminders] = await Promise.all([
      this.repository.audienceProjectionForTasks(ids),
      this.repository.reminderProjectionForTasks(ids),
    ]);
    return rows.map((row) =>
      this.buildDto(
        row,
        audiences.rows.filter((item) => item.task_id === row.id),
        reminders.rows.filter((item) => item.task_id === row.id),
      ),
    );
  }

  private buildDto(
    row: SharedTaskRow | ResolvedSharedTaskRow,
    audiences: Awaited<
      ReturnType<SharedTaskRepository["audienceProjection"]>
    >["rows"],
    reminders: Awaited<
      ReturnType<SharedTaskRepository["reminderProjection"]>
    >["rows"],
  ) {
    return {
      id: row.id,
      title: row.title,
      body: row.body,
      allDay: row.all_day,
      startAt: row.start_at,
      endAt: row.end_at,
      state: row.state,
      isOverdue: isTaskOverdue({
        state: row.state,
        startAt: row.start_at,
        allDay: row.all_day,
      }),
      priority: row.priority,
      linkedEntity:
        row.linked_entity_type && row.linked_entity_id
          ? { type: row.linked_entity_type, id: row.linked_entity_id }
          : null,
      version: Number(row.version),
      createdBy: row.created_by,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      audiences: audiences.map((audience) => ({
        type: audience.audience_type,
        ...(audience.target_id ? { targetId: audience.target_id } : {}),
      })),
      reminders: reminders.map((reminder) => ({
        dueAt: reminder.due_at,
        channel: reminder.channel,
        status: reminder.status,
      })),
      hasReminder: reminders.length > 0,
    };
  }

  private closeDto(row: ResolvedSharedTaskRow): CloseResultRef {
    return {
      taskId: row.id,
      taskVersion: Number(row.version),
      closeId: row.close_id!,
      closedAt: new Date(row.closed_at!).toISOString(),
      closedBy: row.closed_by!,
      closeRequestId: row.close_request_id!,
    };
  }

  private closeRef(
    taskId: string,
    version: number,
    close: TaskCloseRow,
  ): CloseResultRef {
    return {
      taskId,
      taskVersion: version,
      closeId: close.id,
      closedAt: new Date(close.closed_at).toISOString(),
      closedBy: close.closed_by,
      closeRequestId: close.request_id,
    };
  }

  private auditRef(row: SharedTaskRow) {
    return { taskId: row.id, state: row.state, version: Number(row.version) };
  }

  private assertMetadata(metadata: MutationMetadata) {
    if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
      throw new UnprocessableEntityException({
        field: "Idempotency-Key",
        code: "INVALID_IDEMPOTENCY_KEY",
      });
    }
    if (!metadata.requestId || metadata.requestId.length > 128) {
      throw new UnprocessableEntityException({
        field: "X-Request-Id",
        code: "INVALID_REQUEST_ID",
      });
    }
  }

  private invalid(field: string, message: string): never {
    throw new UnprocessableEntityException({
      field,
      code: "INVALID_SHARED_TASK",
      message,
    });
  }

  private deterministicId(seed: string): string {
    const hex = createHash("sha256").update(seed).digest("hex").slice(0, 32).split("");
    hex[12] = "4";
    hex[16] = ["8", "9", "a", "b"][parseInt(hex[16]!, 16) % 4]!;
    const value = hex.join("");
    return `${value.slice(0, 8)}-${value.slice(8, 12)}-${value.slice(12, 16)}-${value.slice(16, 20)}-${value.slice(20)}`;
  }

  private isStaleVersion(error: unknown): boolean {
    if (!(error instanceof ConflictException)) return false;
    const response = error.getResponse();
    return (
      typeof response === "object" &&
      response !== null &&
      "code" in response &&
      response.code === "STALE_VERSION"
    );
  }
}
