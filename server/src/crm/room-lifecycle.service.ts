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
import { RoomLifecycleCommandDto } from "./dto/room-lifecycle.dto";

interface MutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

type QueryRunner = <T extends QueryResultRow>(
  query: string,
  params?: unknown[],
) => Promise<QueryResult<T>>;

interface RoomLifecycleRow extends QueryResultRow {
  id: string;
  branch_id: string | null;
  branch_name: string | null;
  branch_lifecycle_state: "active" | "archived" | null;
  branch_deleted_at: Date | string | null;
  timezone_name: string | null;
  name: string;
  capacity: number | null;
  lifecycle_state: "active" | "archived";
  version: number | string;
  archived_at: Date | string | null;
  archive_reason: string | null;
  archive_effective_date: string | null;
  active_groups: number | string;
  future_lessons: number | string;
  active_series: number | string;
  active_plans: number | string;
  future_conflicts: number | string;
  lesson_history: number | string;
  completed_lessons: number | string;
  ended_series: number | string;
  ended_plans: number | string;
}

interface LifecycleResultRef extends Record<string, unknown> {
  roomId: string;
  lifecycleState: "active" | "archived";
  roomVersion: number;
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

const aggregateType = "organization:room";

@Injectable()
export class RoomLifecycleService {
  constructor(
    private readonly database: DatabaseService,
    private readonly integrity: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
  ) {}

  async preview(actor: ActorContext, roomId: string) {
    this.assertCanManageLifecycle(actor);
    const snapshot = await this.readSnapshot(roomId, (query, params) =>
      this.database.query(query, params),
    );
    return this.toPreview(snapshot);
  }

  async history(actor: ActorContext, roomId: string) {
    this.assertCanManageLifecycle(actor);
    await this.requireRoom(roomId);
    const result = await this.database.query<HistoryRow>(
      `select id, operation, from_state, to_state, version, reason_text,
          effective_date, actor_user_id, request_id, snapshot, created_at
       from app.room_lifecycle_history
       where room_id = $1
       order by created_at desc, id desc
       limit 100`,
      [roomId],
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
    roomId: string,
    dto: RoomLifecycleCommandDto,
    metadata: MutationMetadata,
  ) {
    this.assertCanManageLifecycle(actor);
    this.assertCommand(dto, metadata);
    const initial = await this.readSnapshot(roomId, (query, params) =>
      this.database.query(query, params),
    );
    if (initial.lifecycle_state === "active") {
      this.assertExpectedVersion(initial, dto.expectedVersion);
      this.assertEffectiveDate(dto.effectiveDate, initial.timezone_name);
      this.assertNoArchiveBlockers(initial);
    }
    await this.ensureAggregateVersion(roomId, initial.version);

    const audit: PlatformAuditInput = {
      action: "crm.room_archived",
      entityType: "room",
      entityId: roomId,
      reason: "room.archive",
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
        operation: "crm.room.archive",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType,
        aggregateId: roomId,
        expectedVersion: dto.expectedVersion,
        payload: {
          roomId,
          expectedVersion: dto.expectedVersion,
          reasonText: dto.reasonText.trim(),
          effectiveDate: dto.effectiveDate,
        },
        audit,
        outbox: {
          type: "organization.room.changed",
          payload: {
            entityId: roomId,
            action: "archived",
            effectiveDate: dto.effectiveDate,
          },
        },
        mutate: async (client, nextVersion) => {
          const current = await this.readSnapshot(
            roomId,
            this.clientRunner(client),
            true,
          );
          this.assertExpectedVersion(current, dto.expectedVersion);
          if (current.lifecycle_state !== "active") {
            throw new ConflictException({
              code: "ROOM_ALREADY_ARCHIVED",
              message: "Аудитория уже находится в архиве.",
            });
          }
          this.assertNoArchiveBlockers(current);
          const updated = await client.query<{
            archived_at: Date | string;
            version: number | string;
          }>(
            `update app.rooms
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
              roomId,
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
            roomId,
            lifecycleState: "archived" as const,
            roomVersion: Number(row!.version),
            archivedAt: row!.archived_at,
            effectiveDate: dto.effectiveDate,
          };
          await this.appendHistory(client, {
            roomId,
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
      room: await this.readRoomDto(roomId),
      replayed: result.replayed,
    };
  }

  async restore(
    actor: ActorContext,
    roomId: string,
    dto: RoomLifecycleCommandDto,
    metadata: MutationMetadata,
  ) {
    this.assertCanManageLifecycle(actor);
    this.assertCommand(dto, metadata);
    const initial = await this.readSnapshot(roomId, (query, params) =>
      this.database.query(query, params),
    );
    if (initial.lifecycle_state === "archived") {
      this.assertExpectedVersion(initial, dto.expectedVersion);
      this.assertEffectiveDate(dto.effectiveDate, initial.timezone_name);
      this.assertNoRestoreBlockers(initial);
    }
    await this.ensureAggregateVersion(roomId, initial.version);

    const audit: PlatformAuditInput = {
      action: "crm.room_restored",
      entityType: "room",
      entityId: roomId,
      reason: "room.restore",
      reasonText: dto.reasonText.trim(),
      beforeRef: this.auditRef(initial),
      metadata: { lifecycle: "restored", effectiveDate: dto.effectiveDate },
    };
    const result =
      await this.integrity.executeVersionedMutation<LifecycleResultRef>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        authorization: { actor, capabilityKey: "config.crm.edit" },
        operation: "crm.room.restore",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType,
        aggregateId: roomId,
        expectedVersion: dto.expectedVersion,
        payload: {
          roomId,
          expectedVersion: dto.expectedVersion,
          reasonText: dto.reasonText.trim(),
          effectiveDate: dto.effectiveDate,
        },
        audit,
        outbox: {
          type: "organization.room.changed",
          payload: {
            entityId: roomId,
            action: "restored",
            effectiveDate: dto.effectiveDate,
          },
        },
        mutate: async (client, nextVersion) => {
          const current = await this.readSnapshot(
            roomId,
            this.clientRunner(client),
            true,
          );
          this.assertExpectedVersion(current, dto.expectedVersion);
          if (current.lifecycle_state !== "archived") {
            throw new ConflictException({
              code: "ROOM_NOT_ARCHIVED",
              message: "Аудитория не находится в архиве.",
            });
          }
          this.assertNoRestoreBlockers(current);
          const updated = await client.query<{ version: number | string }>(
            `update app.rooms
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
            [roomId, dto.expectedVersion, nextVersion],
          );
          const row = updated.rows[0];
          if (!row) this.throwStale(dto.expectedVersion, current);
          const after = {
            roomId,
            lifecycleState: "active" as const,
            roomVersion: Number(row!.version),
            effectiveDate: dto.effectiveDate,
          };
          await this.appendHistory(client, {
            roomId,
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
      room: await this.readRoomDto(roomId),
      replayed: result.replayed,
    };
  }

  private async readSnapshot(
    roomId: string,
    query: QueryRunner,
    lock = false,
  ): Promise<RoomLifecycleRow> {
    const result = await query<RoomLifecycleRow>(
      `select room.id, room.branch_id, branch.name as branch_name,
          branch.lifecycle_state as branch_lifecycle_state,
          branch.deleted_at as branch_deleted_at, branch.timezone_name,
          room.name, room.capacity, room.lifecycle_state, room.version,
          room.archived_at, room.archive_reason, room.archive_effective_date,
          (select count(*) from app.groups item
            where item.room_id = room.id and item.deleted_at is null) as active_groups,
          (select count(*) from app.lessons item
            where item.room_id = room.id and item.deleted_at is null
              and item.scheduled_at >= now()
              and item.lifecycle_state in ('scheduled', 'settlement_pending')) as future_lessons,
          (select count(*) from app.schedule_series item
            where item.room_id = room.id and item.deleted_at is null
              and item.superseded_by is null
              and (item.valid_until is null or item.valid_until >= current_date)) as active_series,
          (select count(distinct plan.id)
            from app.schedule_series series
            join app.schedule_plans plan on plan.id = series.plan_id
            where series.room_id = room.id and series.deleted_at is null
              and series.superseded_by is null
              and (series.valid_until is null or series.valid_until >= current_date)
              and plan.status = 'active') as active_plans,
          (select count(*) from app.lessons first_lesson
            join app.lessons second_lesson
              on second_lesson.room_id = first_lesson.room_id
             and second_lesson.id > first_lesson.id
             and second_lesson.deleted_at is null
             and second_lesson.lifecycle_state in ('scheduled', 'settlement_pending')
             and second_lesson.scheduled_at
               < first_lesson.scheduled_at
                 + first_lesson.duration_minutes * interval '1 minute'
             and second_lesson.scheduled_at
                 + second_lesson.duration_minutes * interval '1 minute'
               > first_lesson.scheduled_at
            where first_lesson.room_id = room.id
              and first_lesson.deleted_at is null
              and first_lesson.lifecycle_state in ('scheduled', 'settlement_pending')
              and first_lesson.scheduled_at >= now()) as future_conflicts,
          (select count(*) from app.lessons item
            where item.room_id = room.id) as lesson_history,
          (select count(*) from app.lessons item
            where item.room_id = room.id
              and item.lifecycle_state = 'successfully_completed') as completed_lessons,
          (select count(*) from app.schedule_series item
            where item.room_id = room.id
              and (
                item.deleted_at is not null or item.superseded_by is not null
                or item.valid_until < current_date
              )) as ended_series,
          (select count(distinct plan.id)
            from app.schedule_series series
            join app.schedule_plans plan on plan.id = series.plan_id
            where series.room_id = room.id and plan.status = 'ended') as ended_plans
       from app.rooms room
       left join app.branches branch on branch.id = room.branch_id
       where room.id = $1
       ${lock ? "for update of room" : ""}`,
      [roomId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Аудитория не найдена.");
    return row;
  }

  private toPreview(row: RoomLifecycleRow) {
    const archiveBlockers = this.archiveBlockers(row);
    const restoreBlockers = this.restoreBlockers(row);
    const archived = row.lifecycle_state === "archived";
    return {
      room: this.lifecycleDto(row),
      impact: this.impact(row),
      blockers: archived ? restoreBlockers : archiveBlockers,
      canArchive: !archived && archiveBlockers.length === 0,
      canRestore: archived && restoreBlockers.length === 0,
      confirmRequired: true,
      policy: {
        deletionMode: "archive",
        historicalFactsPreserved: true,
      },
    };
  }

  private archiveBlockers(row: RoomLifecycleRow) {
    const definitions = [
      [
        "ACTIVE_GROUPS",
        "Активные группы",
        row.active_groups,
        "Перенесите или завершите группы.",
      ],
      [
        "FUTURE_LESSONS",
        "Будущие занятия",
        row.future_lessons,
        "Перенесите или отмените будущие занятия.",
      ],
      [
        "ACTIVE_RECURRING_SERIES",
        "Активные серии",
        row.active_series,
        "Перенесите или завершите постоянные серии.",
      ],
      [
        "ACTIVE_SCHEDULE_PLANS",
        "Постоянные планы",
        row.active_plans,
        "Перенесите или завершите постоянные планы.",
      ],
      [
        "FUTURE_ROOM_CONFLICTS",
        "Конфликты расписания",
        row.future_conflicts,
        "Разрешите конфликты будущих занятий.",
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

  private restoreBlockers(row: RoomLifecycleRow) {
    if (
      row.branch_id &&
      row.branch_lifecycle_state === "active" &&
      !row.branch_deleted_at
    ) {
      return [];
    }
    return [
      {
        code: "PARENT_BRANCH_NOT_ACTIVE",
        label: "Филиал недоступен",
        count: 1,
        remediation: "Сначала восстановите родительский филиал.",
      },
    ];
  }

  private impact(row: RoomLifecycleRow) {
    return {
      operational: {
        activeGroups: Number(row.active_groups),
        futureLessons: Number(row.future_lessons),
        activeSeries: Number(row.active_series),
        activePlans: Number(row.active_plans),
        futureConflicts: Number(row.future_conflicts),
      },
      preservedHistory: this.preservedHistory(row),
    };
  }

  private preservedHistory(row: RoomLifecycleRow) {
    return {
      lessons: Number(row.lesson_history),
      completedLessons: Number(row.completed_lessons),
      endedSeries: Number(row.ended_series),
      endedPlans: Number(row.ended_plans),
    };
  }

  private lifecycleDto(row: RoomLifecycleRow) {
    return {
      id: row.id,
      branchId: row.branch_id,
      branchName: row.branch_name,
      name: row.name,
      capacity: row.capacity,
      lifecycleState: row.lifecycle_state,
      version: Number(row.version),
      archivedAt: row.archived_at,
      archiveReason: row.archive_reason,
      archiveEffectiveDate: row.archive_effective_date,
    };
  }

  private auditRef(row: RoomLifecycleRow) {
    return {
      roomId: row.id,
      branchId: row.branch_id,
      name: row.name,
      capacity: row.capacity,
      lifecycleState: row.lifecycle_state,
      roomVersion: Number(row.version),
      archivedAt: row.archived_at,
      archiveEffectiveDate: row.archive_effective_date,
    };
  }

  private async readRoomDto(roomId: string) {
    const row = await this.readSnapshot(roomId, (query, params) =>
      this.database.query(query, params),
    );
    return this.lifecycleDto(row);
  }

  private async requireRoom(roomId: string) {
    const result = await this.database.query(
      "select 1 from app.rooms where id = $1",
      [roomId],
    );
    if (!result.rows[0]) throw new NotFoundException("Аудитория не найдена.");
  }

  private assertCanManageLifecycle(actor: ActorContext) {
    this.policy.assertCanManageSystemSettings(actor);
    if (actor.role !== "director" && actor.role !== "system_admin") {
      throw new ForbiddenException(
        "Архивировать и восстанавливать аудитории может только директор.",
      );
    }
  }

  private assertCommand(
    dto: RoomLifecycleCommandDto,
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
        code: "ROOM_LIFECYCLE_REASON_REQUIRED",
        message: "Укажите причину длиной от 3 до 500 символов.",
      });
    }
    if (dto.confirm !== true) {
      throw new UnprocessableEntityException({
        code: "ROOM_LIFECYCLE_CONFIRMATION_REQUIRED",
        message: "Подтвердите действие после просмотра последствий.",
      });
    }
    if (!Number.isSafeInteger(dto.expectedVersion) || dto.expectedVersion < 1) {
      throw new UnprocessableEntityException({
        code: "ROOM_VERSION_REQUIRED",
        message: "Передайте актуальную версию аудитории.",
      });
    }
    const parsedEffectiveDate = new Date(`${dto.effectiveDate}T00:00:00Z`);
    if (
      !/^\d{4}-\d{2}-\d{2}$/.test(dto.effectiveDate) ||
      Number.isNaN(parsedEffectiveDate.valueOf()) ||
      parsedEffectiveDate.toISOString().slice(0, 10) !== dto.effectiveDate
    ) {
      throw new UnprocessableEntityException({
        code: "ROOM_EFFECTIVE_DATE_REQUIRED",
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
    row: RoomLifecycleRow,
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
        code: "ROOM_EFFECTIVE_DATE_IN_FUTURE",
        message:
          "Отложенное архивирование пока недоступно; выберите сегодня или прошлую дату.",
      });
    }
  }

  private throwStale(expectedVersion: number, row: RoomLifecycleRow): never {
    throw new ConflictException({
      code: "STALE_ROOM_VERSION",
      message: "Аудитория уже изменена в другой вкладке.",
      expectedVersion,
      currentVersion: Number(row.version),
    });
  }

  private assertNoArchiveBlockers(row: RoomLifecycleRow) {
    const blockers = this.archiveBlockers(row);
    if (blockers.length > 0) {
      throw new UnprocessableEntityException({
        code: "ROOM_ARCHIVE_BLOCKED",
        message: "Сначала устраните активные связи аудитории.",
        blockers,
      });
    }
  }

  private assertNoRestoreBlockers(row: RoomLifecycleRow) {
    const blockers = this.restoreBlockers(row);
    if (blockers.length > 0) {
      throw new UnprocessableEntityException({
        code: "ROOM_RESTORE_BLOCKED",
        message: "Аудиторию нельзя восстановить в закрытом филиале.",
        blockers,
      });
    }
  }

  private async ensureAggregateVersion(
    roomId: string,
    version: number | string,
  ) {
    await this.database.query(
      `insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
       values ($1, $2, $3)
       on conflict (aggregate_type, aggregate_id) do nothing`,
      [aggregateType, roomId, Number(version)],
    );
  }

  private clientRunner(client: PoolClient): QueryRunner {
    return <T extends QueryResultRow>(query: string, params?: unknown[]) =>
      client.query<T>(query, params);
  }

  private appendHistory(
    client: PoolClient,
    input: {
      roomId: string;
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
      `insert into app.room_lifecycle_history (
         room_id, operation, from_state, to_state, version, reason_text,
         effective_date, actor_user_id, request_id, snapshot
       ) values ($1, $2, $3, $4, $5, $6, $7::date, $8, $9, $10::jsonb)`,
      [
        input.roomId,
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
