import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { PoolClient, QueryResult, QueryResultRow } from "pg";
import {
  ActorContext,
  ROLE_LEVEL,
  UserRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { PlatformAuditInput } from "../platform/platform-integrity.types";
import { PersonLifecycleCommandDto } from "./dto/person-lifecycle.dto";
import { CrmPolicy } from "./crm.policy";
import { PersonAccountType } from "./person-account.service";

interface MutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

type QueryRunner = <T extends QueryResultRow>(
  query: string,
  params?: unknown[],
) => Promise<QueryResult<T>>;

interface PersonLifecycleRow extends QueryResultRow {
  id: string;
  name: string;
  status: string;
  lifecycle_state: "active" | "archived";
  version: number | string;
  offboarded_at: Date | string | null;
  offboard_reason: string | null;
  lifecycle_previous_status: string | null;
  lifecycle_account_was_active: boolean | null;
  lifecycle_snapshot: Record<string, unknown> | null;
  user_id: string | null;
  app_role: UserRole | null;
  is_app_account: boolean;
  branch_assignments: Array<Record<string, unknown>> | null;
  future_lessons: number | string;
  active_series: number | string;
  active_groups: number | string;
  open_tasks: number | string;
  active_leads: number | string;
  active_overrides: number | string;
  active_sessions: number | string;
}

interface PersonLifecycleRef extends Record<string, unknown> {
  personType: PersonAccountType;
  personId: string;
  lifecycleState: "active" | "archived";
  version: number;
}

interface HistoryRow extends QueryResultRow {
  id: string;
  operation: "offboard" | "restore";
  from_state: "active" | "archived";
  to_state: "active" | "archived";
  version: number | string;
  reason_text: string;
  actor_user_id: string | null;
  request_id: string;
  snapshot: Record<string, unknown>;
  created_at: Date | string;
}

@Injectable()
export class PersonLifecycleService {
  constructor(
    private readonly database: DatabaseService,
    private readonly integrity: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
  ) {}

  async preview(
    actor: ActorContext,
    personType: PersonAccountType,
    personId: string,
  ) {
    this.assertCanManage(actor);
    const row = await this.readSnapshot(
      personType,
      personId,
      (query, params) => this.database.query(query, params),
    );
    this.assertTargetHierarchy(actor, row);
    return this.toPreview(personType, row);
  }

  async history(
    actor: ActorContext,
    personType: PersonAccountType,
    personId: string,
  ) {
    this.assertCanManage(actor);
    const row = await this.readSnapshot(
      personType,
      personId,
      (query, params) => this.database.query(query, params),
    );
    this.assertTargetHierarchy(actor, row);
    const result = await this.database.query<HistoryRow>(
      `select id, operation, from_state, to_state, version, reason_text,
          actor_user_id, request_id, snapshot, created_at
       from app.person_lifecycle_history
       where person_type = $1 and person_id = $2
       order by created_at desc, id desc
       limit 100`,
      [personType, personId],
    );
    return {
      items: result.rows.map((item) => ({
        id: item.id,
        operation: item.operation,
        fromState: item.from_state,
        toState: item.to_state,
        version: Number(item.version),
        reasonText: item.reason_text,
        actorUserId: item.actor_user_id,
        requestId: item.request_id,
        snapshot: item.snapshot,
        createdAt: item.created_at,
      })),
    };
  }

  async offboard(
    actor: ActorContext,
    personType: PersonAccountType,
    personId: string,
    dto: PersonLifecycleCommandDto,
    metadata: MutationMetadata,
  ) {
    this.assertCanManage(actor);
    this.assertCommand(dto, metadata);
    const initial = await this.readSnapshot(
      personType,
      personId,
      (query, params) => this.database.query(query, params),
    );
    this.assertTargetHierarchy(actor, initial);
    if (initial.lifecycle_state === "active") {
      this.assertExpectedVersion(personType, initial, dto.expectedVersion);
      this.assertNoBlockers(personType, initial);
    }
    await this.ensureAggregateVersion(personType, personId, initial.version);

    const audit: PlatformAuditInput = {
      action: `crm.${personType}_offboarded`,
      entityType: personType,
      entityId: personId,
      reason: `${personType}.offboard`,
      reasonText: dto.reasonText.trim(),
      beforeRef: this.auditRef(personType, initial),
    };
    const aggregateType = this.aggregateType(personType);
    const result = await this.integrity.executeVersionedMutation<PersonLifecycleRef>({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "system.settings.manage" },
      operation: `crm.${personType}.offboard`,
      idempotencyKey: metadata.idempotencyKey,
      requestId: metadata.requestId,
      aggregateType,
      aggregateId: personId,
      expectedVersion: dto.expectedVersion,
      payload: {
        personType,
        personId,
        expectedVersion: dto.expectedVersion,
        reasonText: dto.reasonText.trim(),
      },
      audit,
      outbox: {
        type: "organization.person.changed",
        payload: { entityType: personType, entityId: personId, action: "offboarded" },
      },
      mutate: async (client, nextVersion) => {
        const current = await this.readSnapshot(
          personType,
          personId,
          this.clientRunner(client),
          true,
        );
        this.assertTargetHierarchy(actor, current);
        this.assertExpectedVersion(personType, current, dto.expectedVersion);
        if (current.lifecycle_state !== "active") {
          throw new ConflictException({
            code: "PERSON_ALREADY_OFFBOARDED",
            message: "Карточка уже находится в архиве.",
          });
        }
        this.assertNoBlockers(personType, current);
        const lifecycleSnapshot = {
          ...this.auditRef(personType, current),
          branchAssignments: current.branch_assignments ?? [],
        };
        await this.applyOffboarding(client, {
          actor,
          personType,
          personId,
          current,
          nextVersion,
          reasonText: dto.reasonText.trim(),
          lifecycleSnapshot,
        });
        const after: PersonLifecycleRef = {
          personType,
          personId,
          lifecycleState: "archived",
          version: nextVersion,
        };
        await this.appendHistory(client, {
          personType,
          personId,
          operation: "offboard",
          fromState: "active",
          toState: "archived",
          version: nextVersion,
          reasonText: dto.reasonText.trim(),
          actorUserId: actor.userId,
          requestId: metadata.requestId,
          snapshot: lifecycleSnapshot,
        });
        audit.beforeRef = this.auditRef(personType, current);
        audit.afterRef = after;
        return after;
      },
    });
    return {
      preview: await this.preview(actor, personType, personId),
      replayed: result.replayed,
    };
  }

  async restore(
    actor: ActorContext,
    personType: PersonAccountType,
    personId: string,
    dto: PersonLifecycleCommandDto,
    metadata: MutationMetadata,
  ) {
    this.assertCanManage(actor);
    this.assertCommand(dto, metadata);
    const initial = await this.readSnapshot(
      personType,
      personId,
      (query, params) => this.database.query(query, params),
    );
    this.assertTargetHierarchy(actor, initial);
    if (initial.lifecycle_state === "archived") {
      this.assertExpectedVersion(personType, initial, dto.expectedVersion);
    }
    await this.ensureAggregateVersion(personType, personId, initial.version);

    const audit: PlatformAuditInput = {
      action: `crm.${personType}_restored`,
      entityType: personType,
      entityId: personId,
      reason: `${personType}.restore`,
      reasonText: dto.reasonText.trim(),
      beforeRef: this.auditRef(personType, initial),
    };
    const result = await this.integrity.executeVersionedMutation<PersonLifecycleRef>({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "system.settings.manage" },
      operation: `crm.${personType}.restore`,
      idempotencyKey: metadata.idempotencyKey,
      requestId: metadata.requestId,
      aggregateType: this.aggregateType(personType),
      aggregateId: personId,
      expectedVersion: dto.expectedVersion,
      payload: {
        personType,
        personId,
        expectedVersion: dto.expectedVersion,
        reasonText: dto.reasonText.trim(),
      },
      audit,
      outbox: {
        type: "organization.person.changed",
        payload: { entityType: personType, entityId: personId, action: "restored" },
      },
      mutate: async (client, nextVersion) => {
        const current = await this.readSnapshot(
          personType,
          personId,
          this.clientRunner(client),
          true,
        );
        this.assertTargetHierarchy(actor, current);
        this.assertExpectedVersion(personType, current, dto.expectedVersion);
        if (current.lifecycle_state !== "archived") {
          throw new ConflictException({
            code: "PERSON_NOT_OFFBOARDED",
            message: "Карточка не находится в архиве.",
          });
        }
        await this.applyRestore(client, {
          personType,
          personId,
          current,
          nextVersion,
        });
        const after: PersonLifecycleRef = {
          personType,
          personId,
          lifecycleState: "active",
          version: nextVersion,
        };
        await this.appendHistory(client, {
          personType,
          personId,
          operation: "restore",
          fromState: "archived",
          toState: "active",
          version: nextVersion,
          reasonText: dto.reasonText.trim(),
          actorUserId: actor.userId,
          requestId: metadata.requestId,
          snapshot: this.auditRef(personType, current),
        });
        audit.beforeRef = this.auditRef(personType, current);
        audit.afterRef = after;
        return after;
      },
    });
    return {
      preview: await this.preview(actor, personType, personId),
      replayed: result.replayed,
    };
  }

  private async readSnapshot(
    personType: PersonAccountType,
    personId: string,
    query: QueryRunner,
    lock = false,
  ): Promise<PersonLifecycleRow> {
    const lockSql = lock ? "for update of person" : "";
    const result =
      personType === "teacher"
        ? await query<PersonLifecycleRow>(
            `select person.id,
               coalesce(nullif(btrim(concat_ws(' ', profile.last_name, profile.first_name)), ''), person.id::text) as name,
               person.status, person.lifecycle_state, person.version,
               person.offboarded_at, person.offboard_reason,
               person.lifecycle_previous_status,
               person.lifecycle_account_was_active, person.lifecycle_snapshot,
               profile.user_id, account.role::text as app_role,
               coalesce(account.is_app_account, false) as is_app_account,
               (select coalesce(jsonb_agg(jsonb_build_object(
                   'branchId', assignment.branch_id,
                   'activeFrom', assignment.active_from,
                   'activeUntil', assignment.active_until
                 ) order by assignment.branch_id), '[]'::jsonb)
                from app.teacher_branches assignment
                where assignment.teacher_id = person.id
                  and assignment.active_from <= current_date
                  and (assignment.active_until is null or assignment.active_until >= current_date)
               ) as branch_assignments,
               (select count(*) from app.lessons item
                where item.teacher_id = person.id and item.deleted_at is null
                  and item.scheduled_at >= now()
                  and item.lifecycle_state in ('scheduled', 'settlement_pending')) as future_lessons,
               (select count(*) from app.schedule_series item
                where item.teacher_id = person.id and item.deleted_at is null
                  and item.superseded_by is null
                  and (item.valid_until is null or item.valid_until >= current_date)) as active_series,
               (select count(*) from app.groups item
                where item.teacher_id = person.id and item.deleted_at is null
                  and item.lifecycle_state = 'active') as active_groups,
               0::bigint as open_tasks, 0::bigint as active_leads,
               (select count(*) from app.user_capability_overrides item
                where item.user_id = profile.user_id and item.active) as active_overrides,
               (select count(*) from app.refresh_sessions item
                where item.user_id = profile.user_id and item.revoked_at is null
                  and item.expires_at > now()) as active_sessions
             from app.teachers person
             left join app.profiles profile
               on profile.id = person.profile_id and profile.deleted_at is null
             left join app.users account
               on account.id = profile.user_id and account.deleted_at is null
             where person.id = $1 and person.deleted_at is null
             ${lockSql}`,
            [personId],
          )
        : await query<PersonLifecycleRow>(
            `select person.id,
               coalesce(nullif(btrim(concat_ws(' ', profile.last_name, profile.first_name)), ''), person.id::text) as name,
               person.status, person.lifecycle_state, person.version,
               person.offboarded_at, person.offboard_reason,
               person.lifecycle_previous_status,
               person.lifecycle_account_was_active, person.lifecycle_snapshot,
               profile.user_id, account.role::text as app_role,
               coalesce(account.is_app_account, false) as is_app_account,
               (select coalesce(jsonb_agg(jsonb_build_object(
                   'branchId', assignment.branch_id
                 ) order by assignment.branch_id), '[]'::jsonb)
                from app.staff_branch_assignments assignment
                where assignment.staff_member_id = person.id
                  and assignment.deleted_at is null
               ) as branch_assignments,
               0::bigint as future_lessons, 0::bigint as active_series,
               0::bigint as active_groups,
               (select count(*) from app.shared_tasks task
                join app.task_audiences audience on audience.task_id = task.id
                where audience.audience_type = 'user'
                  and audience.target_id = profile.user_id
                  and task.deleted_at is null and task.state <> 'closed') as open_tasks,
               (select count(*) from app.leads item
                where item.assigned_to = profile.user_id
                  and item.deleted_at is null
                  and not exists (
                    select 1 from app.client_conversion_links conversion
                    where conversion.lead_id = item.id
                  )) as active_leads,
               (select count(*) from app.user_capability_overrides item
                where item.user_id = profile.user_id and item.active) as active_overrides,
               (select count(*) from app.refresh_sessions item
                where item.user_id = profile.user_id and item.revoked_at is null
                  and item.expires_at > now()) as active_sessions
             from app.staff_members person
             left join app.profiles profile
               on profile.id = person.profile_id and profile.deleted_at is null
             left join app.users account
               on account.id = profile.user_id and account.deleted_at is null
             where person.id = $1 and person.deleted_at is null
             ${lockSql}`,
            [personId],
          );
    const row = result.rows[0];
    if (!row) {
      throw new NotFoundException(
        personType === "teacher"
          ? "Преподаватель не найден."
          : "Сотрудник не найден.",
      );
    }
    return row;
  }

  private async applyOffboarding(
    client: PoolClient,
    input: {
      actor: ActorContext;
      personType: PersonAccountType;
      personId: string;
      current: PersonLifecycleRow;
      nextVersion: number;
      reasonText: string;
      lifecycleSnapshot: Record<string, unknown>;
    },
  ) {
    const table = input.personType === "teacher" ? "teachers" : "staff_members";
    const archivedStatus = input.personType === "teacher" ? "inactive" : "archived";
    const updated = await client.query(
      `update app.${table}
       set lifecycle_state = 'archived', status = $3,
           lifecycle_previous_status = status,
           lifecycle_account_was_active = $4,
           lifecycle_snapshot = $5::jsonb,
           offboarded_at = now(), offboarded_by = $6,
           offboard_reason = $7, version = $8, updated_at = now()
       where id = $1 and lifecycle_state = 'active' and version = $2`,
      [
        input.personId,
        Number(input.current.version),
        archivedStatus,
        input.current.is_app_account,
        JSON.stringify(input.lifecycleSnapshot),
        input.actor.userId,
        input.reasonText,
        input.nextVersion,
      ],
    );
    if (updated.rowCount !== 1) {
      this.throwStale(input.personType, Number(input.current.version), input.current);
    }

    if (input.personType === "teacher") {
      await client.query(
        `update app.teacher_branches
         set active_until = case
           when active_from < current_date then current_date - 1
           else active_from
         end,
         version = version + 1, updated_at = now()
         where teacher_id = $1 and active_from <= current_date
           and (active_until is null or active_until >= current_date)`,
        [input.personId],
      );
    } else {
      await client.query(
        `update app.staff_branch_assignments
         set deleted_at = now()
         where staff_member_id = $1 and deleted_at is null`,
        [input.personId],
      );
    }
    await this.disableAccount(client, input.current.user_id);
  }

  private async applyRestore(
    client: PoolClient,
    input: {
      personType: PersonAccountType;
      personId: string;
      current: PersonLifecycleRow;
      nextVersion: number;
    },
  ) {
    const table = input.personType === "teacher" ? "teachers" : "staff_members";
    const fallbackStatus = input.personType === "teacher" ? "active" : "working";
    const updated = await client.query(
      `update app.${table}
       set lifecycle_state = 'active',
           status = coalesce(lifecycle_previous_status, $3),
           lifecycle_previous_status = null,
           lifecycle_account_was_active = null,
           lifecycle_snapshot = '{}'::jsonb,
           offboarded_at = null, offboarded_by = null, offboard_reason = null,
           version = $4, updated_at = now()
       where id = $1 and lifecycle_state = 'archived' and version = $2`,
      [input.personId, Number(input.current.version), fallbackStatus, input.nextVersion],
    );
    if (updated.rowCount !== 1) {
      this.throwStale(input.personType, Number(input.current.version), input.current);
    }

    const branchIds = this.snapshotBranchIds(input.current.lifecycle_snapshot);
    if (branchIds.length > 0) {
      if (input.personType === "teacher") {
        await client.query(
          `update app.teacher_branches assignment
           set active_until = null, version = version + 1, updated_at = now()
           from app.branches branch
           where assignment.teacher_id = $1
             and assignment.branch_id = any($2::uuid[])
             and branch.id = assignment.branch_id
             and branch.deleted_at is null and branch.lifecycle_state = 'active'`,
          [input.personId, branchIds],
        );
      } else {
        await client.query(
          `update app.staff_branch_assignments assignment
           set deleted_at = null
           from app.branches branch
           where assignment.staff_member_id = $1
             and assignment.branch_id = any($2::uuid[])
             and branch.id = assignment.branch_id
             and branch.deleted_at is null and branch.lifecycle_state = 'active'`,
          [input.personId, branchIds],
        );
      }
    }
    if (input.current.user_id) {
      await client.query(
        `update app.users
         set is_app_account = $2
           and password_hash is not null
           and lower(email) not like '%@local.magicmusiccrm.invalid'
           and lower(email) not like '%@migration.invalid',
           updated_at = now()
         where id = $1 and deleted_at is null`,
        [input.current.user_id, input.current.lifecycle_account_was_active === true],
      );
      await this.bumpAccessVersion(client, input.current.user_id);
    }
  }

  private async disableAccount(client: PoolClient, userId: string | null) {
    if (!userId) return;
    await client.query(
      `update app.users set is_app_account = false, updated_at = now()
       where id = $1 and deleted_at is null`,
      [userId],
    );
    await client.query(
      `update app.refresh_sessions
       set revoked_at = coalesce(revoked_at, now())
       where user_id = $1 and revoked_at is null`,
      [userId],
    );
    await client.query(
      `update app.user_capability_overrides
       set active = false, revoked_at = now()
       where user_id = $1 and active`,
      [userId],
    );
    await this.bumpAccessVersion(client, userId);
  }

  private bumpAccessVersion(client: PoolClient, userId: string) {
    return client.query(
      `insert into app.user_access_versions (user_id, version, changed_at)
       values ($1, 2, now())
       on conflict (user_id) do update
       set version = app.user_access_versions.version + 1,
           changed_at = now()`,
      [userId],
    );
  }

  private toPreview(personType: PersonAccountType, row: PersonLifecycleRow) {
    const blockers = this.blockers(personType, row);
    return {
      person: {
        id: row.id,
        type: personType,
        name: row.name,
        status: row.status,
        lifecycleState: row.lifecycle_state,
        version: Number(row.version),
        offboardedAt: row.offboarded_at,
        offboardReason: row.offboard_reason,
      },
      account: {
        userId: row.user_id,
        role: row.app_role,
        enabled: row.is_app_account,
        activeSessions: Number(row.active_sessions),
        activeOverrides: Number(row.active_overrides),
      },
      impact: {
        branchAssignments: row.branch_assignments ?? [],
        futureLessons: Number(row.future_lessons),
        activeSeries: Number(row.active_series),
        activeGroups: Number(row.active_groups),
        openTasks: Number(row.open_tasks),
        activeLeads: Number(row.active_leads),
      },
      blockers,
      canOffboard: row.lifecycle_state === "active" && blockers.length === 0,
      confirmRequired: row.lifecycle_state === "active",
    };
  }

  private blockers(personType: PersonAccountType, row: PersonLifecycleRow) {
    const blockers: Array<{ code: string; count: number; message: string }> = [];
    const add = (code: string, value: number | string, message: string) => {
      const count = Number(value);
      if (count > 0) blockers.push({ code, count, message });
    };
    if (personType === "teacher") {
      add("FUTURE_LESSONS", row.future_lessons, "Переназначьте будущие занятия.");
      add("ACTIVE_SERIES", row.active_series, "Завершите или переназначьте постоянное расписание.");
      add("ACTIVE_GROUPS", row.active_groups, "Переназначьте или закройте активные группы.");
    } else {
      add("OPEN_TASKS", row.open_tasks, "Переназначьте открытые персональные задачи.");
      add("ACTIVE_LEADS", row.active_leads, "Передайте активных лидов другому сотруднику.");
    }
    return blockers;
  }

  private assertNoBlockers(personType: PersonAccountType, row: PersonLifecycleRow) {
    const blockers = this.blockers(personType, row);
    if (blockers.length > 0) {
      throw new UnprocessableEntityException({
        code: "PERSON_OFFBOARD_BLOCKED",
        message: "Сначала устраните активную работу сотрудника.",
        blockers,
      });
    }
  }

  private assertTargetHierarchy(actor: ActorContext, row: PersonLifecycleRow) {
    if (row.user_id === actor.userId) {
      throw new ForbiddenException("Нельзя отключить собственную учётную запись.");
    }
    if (!row.app_role) return;
    if (actor.role === "system_admin") return;
    if (ROLE_LEVEL[row.app_role] >= ROLE_LEVEL[actor.role]) {
      throw new ForbiddenException(
        "Директор может управлять жизненным циклом только более низкой роли.",
      );
    }
  }

  private assertCanManage(actor: ActorContext) {
    this.policy.assertCanManageSystemSettings(actor);
    if (actor.role !== "director" && actor.role !== "system_admin") {
      throw new ForbiddenException(
        "Отключение и архивация сотрудников доступны только директору.",
      );
    }
  }

  private assertCommand(dto: PersonLifecycleCommandDto, metadata: MutationMetadata) {
    const reason = dto.reasonText?.trim();
    if (!reason || reason.length < 5 || reason.length > 500 || reason.includes("\0")) {
      throw new UnprocessableEntityException({
        code: "PERSON_LIFECYCLE_REASON_REQUIRED",
        message: "Укажите причину длиной от 5 до 500 символов.",
      });
    }
    if (dto.confirm !== true) {
      throw new UnprocessableEntityException({
        code: "PERSON_LIFECYCLE_CONFIRMATION_REQUIRED",
        message: "Подтвердите действие после просмотра последствий.",
      });
    }
    if (!Number.isSafeInteger(dto.expectedVersion) || dto.expectedVersion < 1) {
      throw new UnprocessableEntityException({
        code: "PERSON_VERSION_REQUIRED",
        message: "Передайте актуальную версию карточки.",
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
    personType: PersonAccountType,
    row: PersonLifecycleRow,
    expectedVersion: number,
  ) {
    if (Number(row.version) !== expectedVersion) {
      this.throwStale(personType, expectedVersion, row);
    }
  }

  private throwStale(
    personType: PersonAccountType,
    expectedVersion: number,
    row: PersonLifecycleRow,
  ): never {
    throw new ConflictException({
      code: "STALE_PERSON_VERSION",
      message:
        personType === "teacher"
          ? "Карточка преподавателя уже изменена."
          : "Карточка сотрудника уже изменена.",
      expectedVersion,
      currentVersion: Number(row.version),
    });
  }

  private auditRef(personType: PersonAccountType, row: PersonLifecycleRow) {
    return {
      personType,
      personId: row.id,
      status: row.status,
      lifecycleState: row.lifecycle_state,
      version: Number(row.version),
      userId: row.user_id,
      accountEnabled: row.is_app_account,
      branchAssignments: row.branch_assignments ?? [],
    };
  }

  private snapshotBranchIds(snapshot: Record<string, unknown> | null) {
    const value = snapshot?.branchAssignments;
    if (!Array.isArray(value)) return [];
    return value
      .map((item) =>
        item && typeof item === "object" && "branchId" in item
          ? String((item as { branchId?: unknown }).branchId ?? "")
          : "",
      )
      .filter(Boolean);
  }

  private aggregateType(personType: PersonAccountType) {
    return `organization:${personType}`;
  }

  private ensureAggregateVersion(
    personType: PersonAccountType,
    personId: string,
    version: number | string,
  ) {
    return this.database.query(
      `insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
       values ($1, $2, $3)
       on conflict (aggregate_type, aggregate_id) do nothing`,
      [this.aggregateType(personType), personId, Number(version)],
    );
  }

  private appendHistory(
    client: PoolClient,
    input: {
      personType: PersonAccountType;
      personId: string;
      operation: "offboard" | "restore";
      fromState: "active" | "archived";
      toState: "active" | "archived";
      version: number;
      reasonText: string;
      actorUserId: string;
      requestId: string;
      snapshot: Record<string, unknown>;
    },
  ) {
    return client.query(
      `insert into app.person_lifecycle_history (
         person_type, person_id, operation, from_state, to_state, version,
         reason_text, actor_user_id, request_id, snapshot
       ) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb)`,
      [
        input.personType,
        input.personId,
        input.operation,
        input.fromState,
        input.toState,
        input.version,
        input.reasonText,
        input.actorUserId,
        input.requestId,
        JSON.stringify(input.snapshot),
      ],
    );
  }

  private clientRunner(client: PoolClient): QueryRunner {
    return <T extends QueryResultRow>(query: string, params?: unknown[]) =>
      client.query<T>(query, params);
  }
}
