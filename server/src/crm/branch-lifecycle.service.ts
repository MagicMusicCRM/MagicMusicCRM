import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { PoolClient, QueryResult, QueryResultRow } from "pg";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { PlatformAuditInput } from "../platform/platform-integrity.types";
import { CrmPolicy } from "./crm.policy";
import { BranchLifecycleCommandDto } from "./dto/branch-lifecycle.dto";

interface MutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

type QueryRunner = <T extends QueryResultRow>(
  query: string,
  params?: unknown[],
) => Promise<QueryResult<T>>;

interface BranchLifecycleRow extends QueryResultRow {
  id: string;
  name: string;
  address: string | null;
  lifecycle_state: "active" | "archived";
  version: number | string;
  archived_at: Date | string | null;
  archive_reason: string | null;
  archive_effective_date: string | null;
  timezone_name: string;
  active_leads: number | string;
  active_students: number | string;
  active_families: number | string;
  active_rooms: number | string;
  active_groups: number | string;
  staff_assignments: number | string;
  teacher_assignments: number | string;
  future_lessons: number | string;
  active_series: number | string;
  open_tasks: number | string;
  active_packages: number | string;
  configuration_drafts: number | string;
  payment_facts: number | string;
  expense_facts: number | string;
  lesson_history: number | string;
  configuration_revisions: number | string;
  chat_history: number | string;
}

interface LifecycleResultRef extends Record<string, unknown> {
  branchId: string;
  lifecycleState: "active" | "archived";
  branchVersion: number;
}

interface HistoryRow extends QueryResultRow {
  id: string;
  operation: "archive" | "restore" | "migration";
  from_state: "active" | "archived";
  to_state: "active" | "archived";
  version: number | string;
  reason_text: string;
  effective_date: string;
  actor_user_id: string | null;
  request_id: string;
  snapshot: Record<string, unknown>;
  created_at: Date | string;
}

const aggregateType = "organization:branch";

@Injectable()
export class BranchLifecycleService {
  constructor(
    private readonly database: DatabaseService,
    private readonly integrity: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
  ) {}

  async preview(actor: ActorContext, branchId: string) {
    this.assertCanManageLifecycle(actor);
    const snapshot = await this.readSnapshot(
      branchId,
      (query, params) => this.database.query(query, params),
    );
    return this.toPreview(snapshot);
  }

  async history(actor: ActorContext, branchId: string) {
    this.assertCanManageLifecycle(actor);
    await this.requireBranch(branchId);
    const result = await this.database.query<HistoryRow>(
      `select id, operation, from_state, to_state, version, reason_text,
          effective_date,
          actor_user_id, request_id, snapshot, created_at
       from app.branch_lifecycle_history
       where branch_id = $1
       order by created_at desc, id desc
       limit 100`,
      [branchId],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        operation: row.operation,
        fromState: row.from_state,
        toState: row.to_state,
        version: Number(row.version),
        reasonText: row.reason_text,
        effectiveDate: row.effective_date,
        actorUserId: row.actor_user_id,
        requestId: row.request_id,
        snapshot: row.snapshot,
        createdAt: row.created_at,
      })),
    };
  }

  async archive(
    actor: ActorContext,
    branchId: string,
    dto: BranchLifecycleCommandDto,
    metadata: MutationMetadata,
  ) {
    this.assertCanManageLifecycle(actor);
    this.assertCommand(dto, metadata);
    const initial = await this.readSnapshot(
      branchId,
      (query, params) => this.database.query(query, params),
    );
    if (initial.lifecycle_state === "active") {
      this.assertExpectedVersion(initial, dto.expectedVersion);
      this.assertEffectiveDate(dto.effectiveDate, initial.timezone_name);
      this.assertNoBlockers(initial);
    }
    await this.ensureAggregateVersion(branchId, initial.version);

    const audit: PlatformAuditInput = {
      action: "crm.branch_archived",
      entityType: "branch",
      entityId: branchId,
      reason: "branch.close",
      reasonText: dto.reasonText.trim(),
      beforeRef: this.auditRef(initial),
      metadata: {
        lifecycle: "archived",
        effectiveDate: dto.effectiveDate,
        preservedHistory: this.preservedHistory(initial),
      },
    };
    const result =
      await this.integrity.executeVersionedMutation<LifecycleResultRef>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        authorization: { actor, capabilityKey: "config.crm.edit" },
        operation: "crm.branch.archive",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType,
        aggregateId: branchId,
        expectedVersion: dto.expectedVersion,
        payload: {
          branchId,
          expectedVersion: dto.expectedVersion,
          reasonText: dto.reasonText.trim(),
          effectiveDate: dto.effectiveDate,
        },
        audit,
        outbox: {
          type: "organization.branch.changed",
          payload: {
            entityId: branchId,
            action: "archived",
            effectiveDate: dto.effectiveDate,
          },
        },
        mutate: async (client, nextVersion) => {
          const current = await this.readSnapshot(
            branchId,
            this.clientRunner(client),
            true,
          );
          this.assertExpectedVersion(current, dto.expectedVersion);
          if (current.lifecycle_state !== "active") {
            throw new ConflictException({
              code: "BRANCH_ALREADY_ARCHIVED",
              message: "Филиал уже находится в архиве.",
            });
          }
          this.assertNoBlockers(current);
          const updated = await client.query<{
            archived_at: Date | string;
            version: number | string;
          }>(
            `update app.branches
             set lifecycle_state = 'archived',
                 deleted_at = now(),
                 archived_at = now(),
                 archived_by = $4,
                 archive_reason = $5,
                 archive_effective_date = $6::date,
                 version = $3,
                 updated_at = now()
             where id = $1 and lifecycle_state = 'active' and version = $2
             returning archived_at, version`,
            [
              branchId,
              dto.expectedVersion,
              nextVersion,
              actor.userId,
              dto.reasonText.trim(),
              dto.effectiveDate,
            ],
          );
          const row = updated.rows[0];
          if (!row) this.throwStale(dto.expectedVersion, current);
          const after = {
            branchId,
            lifecycleState: "archived" as const,
            branchVersion: Number(row!.version),
            archivedAt: row!.archived_at,
            effectiveDate: dto.effectiveDate,
          };
          await this.appendHistory(client, {
            branchId,
            operation: "archive",
            fromState: "active",
            toState: "archived",
            version: nextVersion,
            reasonText: dto.reasonText.trim(),
            effectiveDate: dto.effectiveDate,
            actorUserId: actor.userId,
            requestId: metadata.requestId,
            snapshot: {
              ...this.auditRef(current),
              impact: this.impact(current),
            },
          });
          audit.beforeRef = this.auditRef(current);
          audit.afterRef = after;
          audit.metadata = {
            lifecycle: "archived",
            effectiveDate: dto.effectiveDate,
            preservedHistory: this.preservedHistory(current),
          };
          return after;
        },
      });
    return {
      branch: await this.readBranchDto(branchId),
      replayed: result.replayed,
    };
  }

  async restore(
    actor: ActorContext,
    branchId: string,
    dto: BranchLifecycleCommandDto,
    metadata: MutationMetadata,
  ) {
    this.assertCanManageLifecycle(actor);
    this.assertCommand(dto, metadata);
    const initial = await this.readSnapshot(
      branchId,
      (query, params) => this.database.query(query, params),
    );
    if (initial.lifecycle_state === "archived") {
      this.assertExpectedVersion(initial, dto.expectedVersion);
      this.assertEffectiveDate(dto.effectiveDate, initial.timezone_name);
    }
    await this.ensureAggregateVersion(branchId, initial.version);

    const audit: PlatformAuditInput = {
      action: "crm.branch_restored",
      entityType: "branch",
      entityId: branchId,
      reason: "branch.restore",
      reasonText: dto.reasonText.trim(),
      beforeRef: this.auditRef(initial),
      metadata: { lifecycle: "restored", effectiveDate: dto.effectiveDate },
    };
    const result =
      await this.integrity.executeVersionedMutation<LifecycleResultRef>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        authorization: { actor, capabilityKey: "config.crm.edit" },
        operation: "crm.branch.restore",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType,
        aggregateId: branchId,
        expectedVersion: dto.expectedVersion,
        payload: {
          branchId,
          expectedVersion: dto.expectedVersion,
          reasonText: dto.reasonText.trim(),
          effectiveDate: dto.effectiveDate,
        },
        audit,
        outbox: {
          type: "organization.branch.changed",
          payload: {
            entityId: branchId,
            action: "restored",
            effectiveDate: dto.effectiveDate,
          },
        },
        mutate: async (client, nextVersion) => {
          const current = await this.readSnapshot(
            branchId,
            this.clientRunner(client),
            true,
          );
          this.assertExpectedVersion(current, dto.expectedVersion);
          if (current.lifecycle_state !== "archived") {
            throw new ConflictException({
              code: "BRANCH_NOT_ARCHIVED",
              message: "Филиал не находится в архиве.",
            });
          }
          const updated = await client.query<{ version: number | string }>(
            `update app.branches
             set lifecycle_state = 'active',
                 deleted_at = null,
                 archived_at = null,
                 archived_by = null,
                 archive_reason = null,
                 archive_effective_date = null,
                 version = $3,
                 updated_at = now()
             where id = $1 and lifecycle_state = 'archived' and version = $2
             returning version`,
            [branchId, dto.expectedVersion, nextVersion],
          );
          const row = updated.rows[0];
          if (!row) this.throwStale(dto.expectedVersion, current);
          const after = {
            branchId,
            lifecycleState: "active" as const,
            branchVersion: Number(row!.version),
            effectiveDate: dto.effectiveDate,
          };
          await this.appendHistory(client, {
            branchId,
            operation: "restore",
            fromState: "archived",
            toState: "active",
            version: nextVersion,
            reasonText: dto.reasonText.trim(),
            effectiveDate: dto.effectiveDate,
            actorUserId: actor.userId,
            requestId: metadata.requestId,
            snapshot: this.auditRef(current),
          });
          audit.beforeRef = this.auditRef(current);
          audit.afterRef = after;
          return after;
        },
      });
    return {
      branch: await this.readBranchDto(branchId),
      replayed: result.replayed,
    };
  }

  private async readSnapshot(
    branchId: string,
    query: QueryRunner,
    lock = false,
  ): Promise<BranchLifecycleRow> {
    const result = await query<BranchLifecycleRow>(
      `select branch.id, branch.name, branch.address, branch.timezone_name,
          branch.lifecycle_state, branch.version, branch.archived_at,
          branch.archive_reason, branch.archive_effective_date,
          (select count(*) from app.leads item
            where item.branch_id = branch.id and item.deleted_at is null) as active_leads,
          (select count(*) from app.students item
            where item.branch_id = branch.id and item.deleted_at is null) as active_students,
          (select count(*) from app.families item
            where item.branch_id = branch.id and item.deleted_at is null) as active_families,
          (select count(*) from app.rooms item
            where item.branch_id = branch.id and item.deleted_at is null) as active_rooms,
          (select count(*) from app.groups item
            where item.branch_id = branch.id and item.deleted_at is null) as active_groups,
          (select count(*) from app.staff_branch_assignments item
            where item.branch_id = branch.id and item.deleted_at is null) as staff_assignments,
          (select count(*) from app.teacher_branches item
            where item.branch_id = branch.id
              and item.active_from <= current_date
              and (item.active_until is null or item.active_until >= current_date)) as teacher_assignments,
          (select count(*) from app.lessons item
            where item.branch_id = branch.id and item.deleted_at is null
              and item.scheduled_at >= now()
              and item.lifecycle_state in ('scheduled', 'settlement_pending')) as future_lessons,
          (select count(*) from app.schedule_series item
            where item.branch_id = branch.id and item.deleted_at is null
              and item.superseded_by is null
              and (item.valid_until is null or item.valid_until >= current_date)) as active_series,
          (select count(distinct item.id) from app.shared_tasks item
            where item.deleted_at is null and item.state = 'open'
              and (
                item.branch_id = branch.id
                or exists (
                  select 1 from app.task_audiences audience
                  where audience.task_id = item.id
                    and audience.audience_type = 'branch'
                    and audience.target_id = branch.id
                )
              )) as open_tasks,
          (select count(*) from app.subscription_packages item
            where item.branch_id = branch.id and item.deleted_at is null
              and item.is_active) as active_packages,
          (select count(*) from app.crm_configuration_drafts item
            where item.branch_id = branch.id) as configuration_drafts,
          (select count(*) from app.payments item
            where item.branch_id = branch.id) as payment_facts,
          (select count(*) from app.expenses item
            where item.branch_id = branch.id) as expense_facts,
          (select count(*) from app.lessons item
            where item.branch_id = branch.id) as lesson_history,
          (select count(*) from app.crm_configuration_revisions item
            where item.branch_id = branch.id) as configuration_revisions,
          (select count(*) from app.chats item
            where item.branch_id = branch.id) as chat_history
       from app.branches branch
       where branch.id = $1
       ${lock ? "for update of branch" : ""}`,
      [branchId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Филиал не найден.");
    return row;
  }

  private toPreview(row: BranchLifecycleRow) {
    const blockers = this.blockers(row);
    return {
      branch: this.lifecycleDto(row),
      impact: this.impact(row),
      blockers,
      canClose: row.lifecycle_state === "active" && blockers.length === 0,
      confirmRequired: row.lifecycle_state === "active",
      policy: {
        deletionMode: "archive",
        historicalFactsPreserved: true,
      },
    };
  }

  private blockers(row: BranchLifecycleRow) {
    const definitions = [
      ["ACTIVE_LEADS", "Лиды", row.active_leads, "Перенесите или архивируйте лидов."],
      ["ACTIVE_STUDENTS", "Ученики", row.active_students, "Перенесите или архивируйте учеников."],
      ["ACTIVE_FAMILIES", "Семьи", row.active_families, "Перенесите или архивируйте семейные карточки."],
      ["ACTIVE_ROOMS", "Аудитории", row.active_rooms, "Перенесите или удалите активные аудитории."],
      ["ACTIVE_GROUPS", "Группы", row.active_groups, "Перенесите или завершите группы."],
      ["STAFF_ASSIGNMENTS", "Сотрудники", row.staff_assignments, "Снимите назначения сотрудников."],
      ["TEACHER_ASSIGNMENTS", "Преподаватели", row.teacher_assignments, "Завершите назначения преподавателей."],
      ["FUTURE_LESSONS", "Будущие занятия", row.future_lessons, "Перенесите или отмените будущие занятия."],
      ["ACTIVE_SERIES", "Постоянные планы", row.active_series, "Перенесите или завершите постоянные планы."],
      ["OPEN_TASKS", "Открытые задачи", row.open_tasks, "Закройте или переназначьте задачи филиала."],
      ["ACTIVE_PACKAGES", "Активные абонементы", row.active_packages, "Перенесите или архивируйте пакеты филиала."],
      ["CONFIGURATION_DRAFTS", "Черновики настроек", row.configuration_drafts, "Опубликуйте или удалите черновики настроек."],
    ] as const;
    return definitions
      .map(([code, label, rawCount, remediation]) => ({
        code,
        label,
        count: Number(rawCount),
        remediation,
      }))
      .filter((item) => item.count > 0);
  }

  private impact(row: BranchLifecycleRow) {
    return {
      operational: {
        activeLeads: Number(row.active_leads),
        activeStudents: Number(row.active_students),
        activeFamilies: Number(row.active_families),
        activeRooms: Number(row.active_rooms),
        activeGroups: Number(row.active_groups),
        staffAssignments: Number(row.staff_assignments),
        teacherAssignments: Number(row.teacher_assignments),
        futureLessons: Number(row.future_lessons),
        activeSeries: Number(row.active_series),
        openTasks: Number(row.open_tasks),
        activePackages: Number(row.active_packages),
        configurationDrafts: Number(row.configuration_drafts),
      },
      preservedHistory: this.preservedHistory(row),
    };
  }

  private preservedHistory(row: BranchLifecycleRow) {
    return {
      payments: Number(row.payment_facts),
      expenses: Number(row.expense_facts),
      lessons: Number(row.lesson_history),
      configurationRevisions: Number(row.configuration_revisions),
      chats: Number(row.chat_history),
    };
  }

  private lifecycleDto(row: BranchLifecycleRow) {
    return {
      id: row.id,
      name: row.name,
      address: row.address,
      lifecycleState: row.lifecycle_state,
      version: Number(row.version),
      archivedAt: row.archived_at,
      archiveReason: row.archive_reason,
      archiveEffectiveDate: row.archive_effective_date,
    };
  }

  private auditRef(row: BranchLifecycleRow) {
    return {
      branchId: row.id,
      name: row.name,
      lifecycleState: row.lifecycle_state,
      branchVersion: Number(row.version),
      archivedAt: row.archived_at,
      archiveEffectiveDate: row.archive_effective_date,
    };
  }

  private async readBranchDto(branchId: string) {
    const row = await this.readSnapshot(
      branchId,
      (query, params) => this.database.query(query, params),
    );
    return this.lifecycleDto(row);
  }

  private async requireBranch(branchId: string) {
    const result = await this.database.query(
      "select 1 from app.branches where id = $1",
      [branchId],
    );
    if (!result.rows[0]) throw new NotFoundException("Филиал не найден.");
  }

  private assertCanManageLifecycle(actor: ActorContext) {
    this.policy.assertCanManageSystemSettings(actor);
    if (actor.role !== "director" && actor.role !== "system_admin") {
      throw new ForbiddenException(
        "Закрывать и восстанавливать филиалы может только директор.",
      );
    }
  }

  private assertCommand(
    dto: BranchLifecycleCommandDto,
    metadata: MutationMetadata,
  ) {
    const reason = dto.reasonText?.trim();
    if (!reason || reason.length < 3 || reason.length > 500 || reason.includes("\0")) {
      throw new UnprocessableEntityException({
        code: "BRANCH_LIFECYCLE_REASON_REQUIRED",
        message: "Укажите причину длиной от 3 до 500 символов.",
      });
    }
    if (dto.confirm !== true) {
      throw new UnprocessableEntityException({
        code: "BRANCH_LIFECYCLE_CONFIRMATION_REQUIRED",
        message: "Подтвердите действие после просмотра последствий.",
      });
    }
    if (!Number.isSafeInteger(dto.expectedVersion) || dto.expectedVersion < 1) {
      throw new UnprocessableEntityException({
        code: "BRANCH_VERSION_REQUIRED",
        message: "Передайте актуальную версию филиала.",
      });
    }
    const parsedEffectiveDate = new Date(`${dto.effectiveDate}T00:00:00Z`);
    if (
      !/^\d{4}-\d{2}-\d{2}$/.test(dto.effectiveDate) ||
      Number.isNaN(parsedEffectiveDate.valueOf()) ||
      parsedEffectiveDate.toISOString().slice(0, 10) !== dto.effectiveDate
    ) {
      throw new UnprocessableEntityException({
        code: "BRANCH_EFFECTIVE_DATE_REQUIRED",
        message: "Передайте дату действия в формате YYYY-MM-DD.",
      });
    }
    if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
      throw new UnprocessableEntityException({
        code: "IDEMPOTENCY_KEY_REQUIRED",
        message: "Передайте корректный Idempotency-Key.",
      });
    }
    if (
      !metadata.requestId.trim() ||
      metadata.requestId.length > 160 ||
      /[\r\n\0]/.test(metadata.requestId)
    ) {
      throw new UnprocessableEntityException({
        code: "REQUEST_ID_REQUIRED",
        message: "Передайте корректный X-Request-Id.",
      });
    }
  }

  private assertExpectedVersion(
    row: BranchLifecycleRow,
    expectedVersion: number,
  ) {
    if (Number(row.version) !== expectedVersion) {
      this.throwStale(expectedVersion, row);
    }
  }

  private assertEffectiveDate(effectiveDate: string, timezone: string) {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone || "Europe/Moscow",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(new Date());
    const value = (type: "year" | "month" | "day") =>
      parts.find((part) => part.type === type)?.value ?? "";
    const today = `${value("year")}-${value("month")}-${value("day")}`;
    if (effectiveDate > today) {
      throw new UnprocessableEntityException({
        code: "BRANCH_EFFECTIVE_DATE_IN_FUTURE",
        message:
          "Отложенное закрытие пока недоступно; выберите сегодня или прошлую дату.",
      });
    }
  }

  private throwStale(expectedVersion: number, row: BranchLifecycleRow): never {
    throw new ConflictException({
      code: "STALE_BRANCH_VERSION",
      message: "Филиал уже изменён в другой вкладке.",
      expectedVersion,
      currentVersion: Number(row.version),
    });
  }

  private assertNoBlockers(row: BranchLifecycleRow) {
    const blockers = this.blockers(row);
    if (blockers.length > 0) {
      throw new UnprocessableEntityException({
        code: "BRANCH_CLOSE_BLOCKED",
        message: "Сначала устраните активные связи филиала.",
        blockers,
      });
    }
  }

  private async ensureAggregateVersion(branchId: string, version: number | string) {
    await this.database.query(
      `insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
       values ($1, $2, $3)
       on conflict (aggregate_type, aggregate_id) do nothing`,
      [aggregateType, branchId, Number(version)],
    );
  }

  private clientRunner(client: PoolClient): QueryRunner {
    return <T extends QueryResultRow>(query: string, params?: unknown[]) =>
      client.query<T>(query, params);
  }

  private appendHistory(
    client: PoolClient,
    input: {
      branchId: string;
      operation: "archive" | "restore";
      fromState: "active" | "archived";
      toState: "active" | "archived";
      version: number;
      reasonText: string;
      effectiveDate: string;
      actorUserId: string;
      requestId: string;
      snapshot: Record<string, unknown>;
    },
  ) {
    return client.query(
      `insert into app.branch_lifecycle_history (
         branch_id, operation, from_state, to_state, version, reason_text,
         effective_date, actor_user_id, request_id, snapshot
       ) values ($1, $2, $3, $4, $5, $6, $7::date, $8, $9, $10::jsonb)`,
      [
        input.branchId,
        input.operation,
        input.fromState,
        input.toState,
        input.version,
        input.reasonText,
        input.effectiveDate,
        input.actorUserId,
        input.requestId,
        JSON.stringify(input.snapshot),
      ],
    );
  }
}
