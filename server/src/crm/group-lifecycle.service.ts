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
import { GroupLifecycleCommandDto } from "./dto/group-lifecycle.dto";
import { assertSettingsBranchScope } from "./settings-branch-scope";

interface MutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

type QueryRunner = <T extends QueryResultRow>(
  query: string,
  params?: unknown[],
) => Promise<QueryResult<T>>;

interface GroupLifecycleRow extends QueryResultRow {
  id: string;
  teacher_id: string | null;
  teacher_name: string | null;
  teacher_assignment_active: boolean;
  branch_id: string | null;
  branch_name: string | null;
  branch_lifecycle_state: "active" | "archived" | null;
  branch_deleted_at: Date | string | null;
  timezone_name: string | null;
  room_id: string | null;
  room_name: string | null;
  room_branch_id: string | null;
  room_lifecycle_state: "active" | "archived" | null;
  room_deleted_at: Date | string | null;
  name: string;
  price_per_lesson: number | string | null;
  teacher_rate: number | string | null;
  lifecycle_state: "active" | "archived";
  version: number | string;
  archived_at: Date | string | null;
  archive_reason: string | null;
  archive_effective_date: string | null;
  active_members: number | string;
  membership_history: number | string;
  future_lessons: number | string;
  active_series: number | string;
  active_plans: number | string;
  lesson_history: number | string;
  completed_lessons: number | string;
  ended_series: number | string;
  ended_plans: number | string;
}

interface LifecycleResultRef extends Record<string, unknown> {
  groupId: string;
  lifecycleState: "active" | "archived";
  groupVersion: number;
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

const aggregateType = "organization:group";

@Injectable()
export class GroupLifecycleService {
  constructor(
    private readonly database: DatabaseService,
    private readonly integrity: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
  ) {}

  async preview(actor: ActorContext, groupId: string) {
    this.policy.assertCanManageSystemSettings(actor);
    const snapshot = await this.readSnapshot(groupId, (query, params) =>
      this.database.query(query, params),
    );
    await this.assertScope(actor, snapshot.branch_id);
    return this.toPreview(snapshot);
  }

  async history(actor: ActorContext, groupId: string) {
    this.policy.assertCanManageSystemSettings(actor);
    const snapshot = await this.readSnapshot(groupId, (query, params) =>
      this.database.query(query, params),
    );
    await this.assertScope(actor, snapshot.branch_id);
    const result = await this.database.query<HistoryRow>(
      `select id, operation, from_state, to_state, version, reason_text,
          effective_date, actor_user_id, request_id, snapshot, created_at
       from app.group_lifecycle_history
       where group_id = $1
       order by created_at desc, id desc
       limit 100`,
      [groupId],
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
    groupId: string,
    dto: GroupLifecycleCommandDto,
    metadata: MutationMetadata,
  ) {
    this.policy.assertCanManageSystemSettings(actor);
    this.assertCommand(dto, metadata);
    const initial = await this.readSnapshot(groupId, (query, params) =>
      this.database.query(query, params),
    );
    await this.assertScope(actor, initial.branch_id);
    if (initial.lifecycle_state === "active") {
      this.assertExpectedVersion(initial, dto.expectedVersion);
      this.assertEffectiveDate(dto.effectiveDate, initial.timezone_name);
      this.assertNoArchiveBlockers(initial);
    }
    await this.ensureAggregateVersion(groupId, initial.version);

    const audit: PlatformAuditInput = {
      action: "crm.group_archived",
      entityType: "group",
      entityId: groupId,
      reason: "group.archive",
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
        authorization: { actor, capabilityKey: "system.settings.manage" },
        operation: "crm.group.archive",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType,
        aggregateId: groupId,
        expectedVersion: dto.expectedVersion,
        payload: {
          groupId,
          expectedVersion: dto.expectedVersion,
          reasonText: dto.reasonText.trim(),
          effectiveDate: dto.effectiveDate,
        },
        audit,
        outbox: {
          type: "organization.group.changed",
          payload: {
            entityId: groupId,
            action: "archived",
            effectiveDate: dto.effectiveDate,
          },
        },
        mutate: async (client, nextVersion) => {
          const current = await this.readSnapshot(
            groupId,
            this.clientRunner(client),
            true,
          );
          await this.assertScope(actor, current.branch_id);
          this.assertExpectedVersion(current, dto.expectedVersion);
          if (current.lifecycle_state !== "active") {
            throw new ConflictException({
              code: "GROUP_ALREADY_ARCHIVED",
              message: "Группа уже завершена и находится в архиве.",
            });
          }
          this.assertNoArchiveBlockers(current);
          const updated = await client.query<{
            archived_at: Date | string;
            version: number | string;
          }>(
            `update app.groups
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
              groupId,
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
            groupId,
            lifecycleState: "archived" as const,
            groupVersion: Number(row!.version),
            archivedAt: row!.archived_at,
            effectiveDate: dto.effectiveDate,
          };
          await this.appendHistory(client, {
            groupId,
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
          return after;
        },
      });
    return {
      group: await this.readGroupDto(groupId),
      replayed: result.replayed,
    };
  }

  async restore(
    actor: ActorContext,
    groupId: string,
    dto: GroupLifecycleCommandDto,
    metadata: MutationMetadata,
  ) {
    this.policy.assertCanManageSystemSettings(actor);
    this.assertCommand(dto, metadata);
    const initial = await this.readSnapshot(groupId, (query, params) =>
      this.database.query(query, params),
    );
    await this.assertScope(actor, initial.branch_id);
    if (initial.lifecycle_state === "archived") {
      this.assertExpectedVersion(initial, dto.expectedVersion);
      this.assertEffectiveDate(dto.effectiveDate, initial.timezone_name);
      this.assertNoRestoreBlockers(initial);
    }
    await this.ensureAggregateVersion(groupId, initial.version);

    const audit: PlatformAuditInput = {
      action: "crm.group_restored",
      entityType: "group",
      entityId: groupId,
      reason: "group.restore",
      reasonText: dto.reasonText.trim(),
      beforeRef: this.auditRef(initial),
      metadata: { lifecycle: "restored", effectiveDate: dto.effectiveDate },
    };
    const result =
      await this.integrity.executeVersionedMutation<LifecycleResultRef>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        authorization: { actor, capabilityKey: "system.settings.manage" },
        operation: "crm.group.restore",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType,
        aggregateId: groupId,
        expectedVersion: dto.expectedVersion,
        payload: {
          groupId,
          expectedVersion: dto.expectedVersion,
          reasonText: dto.reasonText.trim(),
          effectiveDate: dto.effectiveDate,
        },
        audit,
        outbox: {
          type: "organization.group.changed",
          payload: {
            entityId: groupId,
            action: "restored",
            effectiveDate: dto.effectiveDate,
          },
        },
        mutate: async (client, nextVersion) => {
          const current = await this.readSnapshot(
            groupId,
            this.clientRunner(client),
            true,
          );
          await this.assertScope(actor, current.branch_id);
          this.assertExpectedVersion(current, dto.expectedVersion);
          if (current.lifecycle_state !== "archived") {
            throw new ConflictException({
              code: "GROUP_NOT_ARCHIVED",
              message: "Группа не находится в архиве.",
            });
          }
          this.assertNoRestoreBlockers(current);
          const updated = await client.query<{ version: number | string }>(
            `update app.groups
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
            [groupId, dto.expectedVersion, nextVersion],
          );
          const row = updated.rows[0];
          if (!row) this.throwStale(dto.expectedVersion, current);
          const after = {
            groupId,
            lifecycleState: "active" as const,
            groupVersion: Number(row!.version),
            effectiveDate: dto.effectiveDate,
          };
          await this.appendHistory(client, {
            groupId,
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
      group: await this.readGroupDto(groupId),
      replayed: result.replayed,
    };
  }

  private async readSnapshot(
    groupId: string,
    query: QueryRunner,
    lock = false,
  ): Promise<GroupLifecycleRow> {
    const result = await query<GroupLifecycleRow>(
      `select target.id, target.teacher_id,
          trim(coalesce(profile.first_name, '') || ' ' || coalesce(profile.last_name, '')) as teacher_name,
          exists (
            select 1 from app.teacher_branches assignment
            where assignment.teacher_id = target.teacher_id
              and assignment.branch_id = target.branch_id
              and assignment.active_from <= current_date
              and (assignment.active_until is null or assignment.active_until >= current_date)
          ) and teacher.deleted_at is null
            and lower(coalesce(teacher.status, '')) in ('active', 'working', 'активен', 'работает')
            as teacher_assignment_active,
          target.branch_id, branch.name as branch_name,
          branch.lifecycle_state as branch_lifecycle_state,
          branch.deleted_at as branch_deleted_at, branch.timezone_name,
          target.room_id, room.name as room_name, room.branch_id as room_branch_id,
          room.lifecycle_state as room_lifecycle_state,
          room.deleted_at as room_deleted_at,
          target.name, target.price_per_lesson, target.teacher_rate,
          target.lifecycle_state, target.version, target.archived_at,
          target.archive_reason, target.archive_effective_date,
          (select count(*) from app.group_students item
            where item.group_id = target.id and item.left_at is null) as active_members,
          (select count(*) from app.group_students item
            where item.group_id = target.id) as membership_history,
          (select count(*) from app.lessons item
            where item.group_id = target.id and item.deleted_at is null
              and item.scheduled_at >= now()
              and item.lifecycle_state in ('scheduled', 'settlement_pending')) as future_lessons,
          (select count(*) from app.schedule_series item
            where item.group_id = target.id and item.deleted_at is null
              and item.superseded_by is null
              and (item.valid_until is null or item.valid_until >= current_date)) as active_series,
          (select count(*) from app.schedule_plans item
            where item.group_id = target.id and item.status = 'active') as active_plans,
          (select count(*) from app.lessons item
            where item.group_id = target.id) as lesson_history,
          (select count(*) from app.lessons item
            where item.group_id = target.id
              and item.lifecycle_state = 'successfully_completed') as completed_lessons,
          (select count(*) from app.schedule_series item
            where item.group_id = target.id
              and (item.deleted_at is not null or item.superseded_by is not null
                or item.valid_until < current_date)) as ended_series,
          (select count(*) from app.schedule_plans item
            where item.group_id = target.id and item.status = 'ended') as ended_plans
       from app.groups target
       left join app.branches branch on branch.id = target.branch_id
       left join app.rooms room on room.id = target.room_id
       left join app.teachers teacher on teacher.id = target.teacher_id
       left join app.profiles profile on profile.id = teacher.profile_id
       where target.id = $1
       ${lock ? "for update of target" : ""}`,
      [groupId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Группа не найдена.");
    return row;
  }

  private toPreview(row: GroupLifecycleRow) {
    const archiveBlockers = this.archiveBlockers(row);
    const restoreBlockers = this.restoreBlockers(row);
    const archived = row.lifecycle_state === "archived";
    return {
      group: this.lifecycleDto(row),
      impact: this.impact(row),
      blockers: archived ? restoreBlockers : archiveBlockers,
      canArchive: !archived && archiveBlockers.length === 0,
      canRestore: archived && restoreBlockers.length === 0,
      confirmRequired: true,
      policy: {
        deletionMode: "archive",
        rosterPreserved: true,
        historicalFactsPreserved: true,
      },
    };
  }

  private archiveBlockers(row: GroupLifecycleRow) {
    const definitions = [
      [
        "FUTURE_LESSONS",
        "Будущие занятия",
        row.future_lessons,
        "Перенесите или отмените будущие занятия группы.",
      ],
      [
        "ACTIVE_RECURRING_SERIES",
        "Активные серии",
        row.active_series,
        "Завершите постоянные серии группы.",
      ],
      [
        "ACTIVE_SCHEDULE_PLANS",
        "Постоянные планы",
        row.active_plans,
        "Завершите постоянные планы группы.",
      ],
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

  private restoreBlockers(row: GroupLifecycleRow) {
    const blockers: Array<{
      code: string;
      label: string;
      count: number;
      remediation: string;
    }> = [];
    if (
      !row.branch_id ||
      row.branch_lifecycle_state !== "active" ||
      row.branch_deleted_at
    ) {
      blockers.push({
        code: "PARENT_BRANCH_NOT_ACTIVE",
        label: "Филиал недоступен",
        count: 1,
        remediation: "Сначала восстановите родительский филиал.",
      });
    }
    if (
      !row.room_id ||
      row.room_lifecycle_state !== "active" ||
      row.room_deleted_at ||
      row.room_branch_id !== row.branch_id
    ) {
      blockers.push({
        code: "GROUP_ROOM_NOT_ACTIVE",
        label: "Аудитория недоступна",
        count: 1,
        remediation: "Выберите активную аудиторию этого филиала.",
      });
    }
    if (!row.teacher_id || !row.teacher_assignment_active) {
      blockers.push({
        code: "GROUP_TEACHER_NOT_ACTIVE",
        label: "Преподаватель недоступен",
        count: 1,
        remediation: "Назначьте активного преподавателя в филиал группы.",
      });
    }
    return blockers;
  }

  private impact(row: GroupLifecycleRow) {
    return {
      operational: {
        activeMembers: Number(row.active_members),
        futureLessons: Number(row.future_lessons),
        activeSeries: Number(row.active_series),
        activePlans: Number(row.active_plans),
      },
      preservedHistory: this.preservedHistory(row),
    };
  }

  private preservedHistory(row: GroupLifecycleRow) {
    return {
      memberships: Number(row.membership_history),
      lessons: Number(row.lesson_history),
      completedLessons: Number(row.completed_lessons),
      endedSeries: Number(row.ended_series),
      endedPlans: Number(row.ended_plans),
    };
  }

  private lifecycleDto(row: GroupLifecycleRow) {
    return {
      id: row.id,
      teacherId: row.teacher_id,
      teacherName: row.teacher_name,
      branchId: row.branch_id,
      branchName: row.branch_name,
      roomId: row.room_id,
      roomName: row.room_name,
      name: row.name,
      pricePerLesson:
        row.price_per_lesson === null ? null : Number(row.price_per_lesson),
      teacherRate:
        row.teacher_rate === null ? null : Number(row.teacher_rate),
      studentsCount: Number(row.active_members),
      lifecycleState: row.lifecycle_state,
      version: Number(row.version),
      archivedAt: row.archived_at,
      archiveReason: row.archive_reason,
      archiveEffectiveDate: row.archive_effective_date,
    };
  }

  private auditRef(row: GroupLifecycleRow) {
    return {
      groupId: row.id,
      teacherId: row.teacher_id,
      branchId: row.branch_id,
      roomId: row.room_id,
      name: row.name,
      lifecycleState: row.lifecycle_state,
      groupVersion: Number(row.version),
      archivedAt: row.archived_at,
      archiveEffectiveDate: row.archive_effective_date,
    };
  }

  private async readGroupDto(groupId: string) {
    const row = await this.readSnapshot(groupId, (query, params) =>
      this.database.query(query, params),
    );
    return this.lifecycleDto(row);
  }

  private async assertScope(actor: ActorContext, branchId: string | null) {
    if (!branchId) {
      if (actor.role === "manager") {
        throw new ForbiddenException("Группа не относится к доступному филиалу.");
      }
      return;
    }
    await assertSettingsBranchScope(this.database, actor, branchId);
  }

  private assertCommand(
    dto: GroupLifecycleCommandDto,
    metadata: MutationMetadata,
  ) {
    const reason = dto.reasonText?.trim();
    if (
      !reason ||
      reason.length < 3 ||
      reason.length > 500 ||
      reason.includes("\0")
    ) {
      throw new UnprocessableEntityException({
        code: "GROUP_LIFECYCLE_REASON_REQUIRED",
        message: "Укажите причину длиной от 3 до 500 символов.",
      });
    }
    if (dto.confirm !== true) {
      throw new UnprocessableEntityException({
        code: "GROUP_LIFECYCLE_CONFIRMATION_REQUIRED",
        message: "Подтвердите действие после просмотра последствий.",
      });
    }
    if (!Number.isSafeInteger(dto.expectedVersion) || dto.expectedVersion < 1) {
      throw new UnprocessableEntityException({
        code: "GROUP_VERSION_REQUIRED",
        message: "Передайте актуальную версию группы.",
      });
    }
    const parsedEffectiveDate = new Date(`${dto.effectiveDate}T00:00:00Z`);
    if (
      !/^\d{4}-\d{2}-\d{2}$/.test(dto.effectiveDate) ||
      Number.isNaN(parsedEffectiveDate.valueOf()) ||
      parsedEffectiveDate.toISOString().slice(0, 10) !== dto.effectiveDate
    ) {
      throw new UnprocessableEntityException({
        code: "GROUP_EFFECTIVE_DATE_REQUIRED",
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
    row: GroupLifecycleRow,
    expectedVersion: number,
  ) {
    if (Number(row.version) !== expectedVersion) {
      this.throwStale(expectedVersion, row);
    }
  }

  private assertEffectiveDate(effectiveDate: string, timezone: string | null) {
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
        code: "GROUP_EFFECTIVE_DATE_IN_FUTURE",
        message:
          "Отложенное завершение пока недоступно; выберите сегодня или прошлую дату.",
      });
    }
  }

  private throwStale(expectedVersion: number, row: GroupLifecycleRow): never {
    throw new ConflictException({
      code: "STALE_GROUP_VERSION",
      message: "Группа уже изменена в другой вкладке.",
      expectedVersion,
      currentVersion: Number(row.version),
    });
  }

  private assertNoArchiveBlockers(row: GroupLifecycleRow) {
    const blockers = this.archiveBlockers(row);
    if (blockers.length > 0) {
      throw new UnprocessableEntityException({
        code: "GROUP_ARCHIVE_BLOCKED",
        message: "Сначала завершите активное расписание группы.",
        blockers,
      });
    }
  }

  private assertNoRestoreBlockers(row: GroupLifecycleRow) {
    const blockers = this.restoreBlockers(row);
    if (blockers.length > 0) {
      throw new UnprocessableEntityException({
        code: "GROUP_RESTORE_BLOCKED",
        message: "Группу нельзя восстановить с недоступными назначениями.",
        blockers,
      });
    }
  }

  private async ensureAggregateVersion(
    groupId: string,
    version: number | string,
  ) {
    await this.database.query(
      `insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
       values ($1, $2, $3)
       on conflict (aggregate_type, aggregate_id) do nothing`,
      [aggregateType, groupId, Number(version)],
    );
  }

  private clientRunner(client: PoolClient): QueryRunner {
    return <T extends QueryResultRow>(query: string, params?: unknown[]) =>
      client.query<T>(query, params);
  }

  private appendHistory(
    client: PoolClient,
    input: {
      groupId: string;
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
      `insert into app.group_lifecycle_history (
         group_id, operation, from_state, to_state, version, reason_text,
         effective_date, actor_user_id, request_id, snapshot
       ) values ($1, $2, $3, $4, $5, $6, $7::date, $8, $9, $10::jsonb)`,
      [
        input.groupId,
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
