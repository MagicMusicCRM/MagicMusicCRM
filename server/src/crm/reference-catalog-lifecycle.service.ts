import {
  ConflictException,
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
import {
  ReferenceCatalogLifecycleCommandDto,
  RenameReferenceCatalogItemDto,
} from "./dto/reference-catalog-lifecycle.dto";
import { assertSettingsBranchScope } from "./settings-branch-scope";

export type ReferenceCatalogEntityType =
  | "discipline"
  | "loss_reason"
  | "branch_discipline";

interface MutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

type QueryRunner = <T extends QueryResultRow>(
  query: string,
  params?: unknown[],
) => Promise<QueryResult<T>>;

interface ReferenceSnapshot extends QueryResultRow {
  id: string;
  name: string;
  kind: string | null;
  sort_order: number | string | null;
  color: string | null;
  branch_id: string | null;
  branch_name: string | null;
  branch_lifecycle_state: string | null;
  discipline_id: string | null;
  discipline_lifecycle_state: string | null;
  lifecycle_state: "active" | "archived";
  version: number | string;
  archived_at: Date | string | null;
  archive_reason: string | null;
  active_branch_assignments: number | string;
  active_teacher_assignments: number | string;
  active_student_assignments: number | string;
  active_packages: number | string;
  historical_branch_assignments: number | string;
  historical_teacher_assignments: number | string;
  historical_student_assignments: number | string;
  historical_packages: number | string;
  historical_uses: number | string;
}

interface HistoryRow extends QueryResultRow {
  id: string;
  entity_type: ReferenceCatalogEntityType;
  entity_id: string;
  operation: "rename" | "archive" | "restore" | "unassign" | "migration";
  from_state: "active" | "archived";
  to_state: "active" | "archived";
  version: number | string;
  reason_text: string;
  actor_user_id: string | null;
  request_id: string;
  snapshot: Record<string, unknown>;
  created_at: Date | string;
}

interface MutationResultRef extends Record<string, unknown> {
  entityType: ReferenceCatalogEntityType;
  entityId: string;
  lifecycleState: "active" | "archived";
  entityVersion: number;
}

@Injectable()
export class ReferenceCatalogLifecycleService {
  constructor(
    private readonly database: DatabaseService,
    private readonly integrity: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
  ) {}

  async preview(
    actor: ActorContext,
    entityType: ReferenceCatalogEntityType,
    entityId: string,
  ) {
    this.assertCanManage(actor);
    const snapshot = await this.readSnapshot(
      entityType,
      entityId,
      (query, params) => this.database.query(query, params),
    );
    await this.assertBranchScope(actor, entityType, snapshot.branch_id);
    return this.toPreview(entityType, snapshot);
  }

  async history(
    actor: ActorContext,
    entityType: ReferenceCatalogEntityType,
    entityId: string,
  ) {
    this.assertCanManage(actor);
    const snapshot = await this.readSnapshot(
      entityType,
      entityId,
      (query, params) => this.database.query(query, params),
    );
    await this.assertBranchScope(actor, entityType, snapshot.branch_id);
    const result = await this.database.query<HistoryRow>(
      `select id, entity_type, entity_id, operation, from_state, to_state,
          version, reason_text, actor_user_id, request_id, snapshot, created_at
       from app.reference_catalog_history
       where entity_type = $1 and entity_id = $2
       order by created_at desc, id desc
       limit 100`,
      [entityType, entityId],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        entityType: row.entity_type,
        entityId: row.entity_id,
        operation: row.operation,
        fromState: row.from_state,
        toState: row.to_state,
        version: Number(row.version),
        reasonText: row.reason_text,
        actorUserId: row.actor_user_id,
        requestId: row.request_id,
        snapshot: row.snapshot,
        createdAt: row.created_at,
      })),
    };
  }

  async rename(
    actor: ActorContext,
    entityType: Exclude<ReferenceCatalogEntityType, "branch_discipline">,
    entityId: string,
    dto: RenameReferenceCatalogItemDto,
    metadata: MutationMetadata,
  ) {
    this.assertCanManage(actor);
    this.assertCommand(dto, metadata);
    const name = dto.name.trim();
    if (!name) {
      throw new UnprocessableEntityException({
        code: "REFERENCE_NAME_REQUIRED",
        message: "Название обязательно.",
      });
    }
    const initial = await this.readSnapshot(
      entityType,
      entityId,
      (query, params) => this.database.query(query, params),
    );
    this.assertExpectedVersion(entityType, initial, dto.expectedVersion);
    if (initial.name === name) {
      throw new UnprocessableEntityException({
        code: "REFERENCE_NAME_UNCHANGED",
        message: "Укажите новое название.",
      });
    }
    await this.ensureAggregateVersion(entityType, entityId, initial.version);

    const audit = this.auditInput(
      actor,
      entityType,
      initial,
      "renamed",
      dto.reasonText,
    );
    try {
      const result = await this.integrity.executeVersionedMutation<MutationResultRef>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        authorization: { actor, capabilityKey: "config.crm.edit" },
        operation: `crm.reference.${entityType}.rename`,
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType: this.aggregateType(entityType),
        aggregateId: entityId,
        expectedVersion: dto.expectedVersion,
        payload: {
          entityType,
          entityId,
          expectedVersion: dto.expectedVersion,
          name,
          reasonText: dto.reasonText.trim(),
        },
        audit,
        outbox: {
          type: "reference.catalog.changed",
          payload: { entityType, entityId, action: "renamed" },
        },
        mutate: async (client, nextVersion) => {
          const current = await this.readSnapshot(
            entityType,
            entityId,
            this.clientRunner(client),
            true,
          );
          this.assertExpectedVersion(entityType, current, dto.expectedVersion);
          await this.assertNameAvailable(
            client,
            entityType,
            entityId,
            name,
            current.kind,
          );
          const table = entityType === "discipline" ? "disciplines" : "lead_loss_reasons";
          const updated = await client.query<{ version: number | string }>(
            `update app.${table}
             set name = $3, version = $4, updated_at = now()
             where id = $1 and version = $2
             returning version`,
            [entityId, dto.expectedVersion, name, nextVersion],
          );
          if (!updated.rows[0]) this.throwStale(entityType, dto.expectedVersion, current);
          await this.appendHistory(client, {
            entityType,
            entityId,
            operation: "rename",
            fromState: current.lifecycle_state,
            toState: current.lifecycle_state,
            version: nextVersion,
            reasonText: dto.reasonText.trim(),
            actorUserId: actor.userId,
            requestId: metadata.requestId,
            snapshot: {
              before: this.auditRef(entityType, current),
              after: { name },
            },
          });
          const after: MutationResultRef = {
            entityType,
            entityId,
            lifecycleState: current.lifecycle_state,
            entityVersion: nextVersion,
            name,
          };
          audit.beforeRef = this.auditRef(entityType, current);
          audit.afterRef = after;
          return after;
        },
      });
      return {
        preview: await this.preview(actor, entityType, entityId),
        replayed: result.replayed,
      };
    } catch (error) {
      this.translateUniqueViolation(error);
      throw error;
    }
  }

  async archive(
    actor: ActorContext,
    entityType: ReferenceCatalogEntityType,
    entityId: string,
    dto: ReferenceCatalogLifecycleCommandDto,
    metadata: MutationMetadata,
  ) {
    this.assertCanManage(actor);
    this.assertCommand(dto, metadata);
    const initial = await this.readSnapshot(
      entityType,
      entityId,
      (query, params) => this.database.query(query, params),
    );
    await this.assertBranchScope(actor, entityType, initial.branch_id);
    this.assertExpectedVersion(entityType, initial, dto.expectedVersion);
    if (initial.lifecycle_state !== "active") {
      throw new ConflictException({
        code: "REFERENCE_ALREADY_ARCHIVED",
        message: this.archivePastMessage(entityType),
      });
    }
    this.assertNoArchiveBlockers(entityType, initial);
    await this.ensureAggregateVersion(entityType, entityId, initial.version);

    const action = entityType === "branch_discipline" ? "unassigned" : "archived";
    const audit = this.auditInput(
      actor,
      entityType,
      initial,
      action,
      dto.reasonText,
    );
    const result = await this.integrity.executeVersionedMutation<MutationResultRef>({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "config.crm.edit" },
      operation: `crm.reference.${entityType}.${action}`,
      idempotencyKey: metadata.idempotencyKey,
      requestId: metadata.requestId,
      aggregateType: this.aggregateType(entityType),
      aggregateId: entityId,
      expectedVersion: dto.expectedVersion,
      payload: {
        entityType,
        entityId,
        expectedVersion: dto.expectedVersion,
        reasonText: dto.reasonText.trim(),
      },
      audit,
      outbox: {
        type: "reference.catalog.changed",
        payload: { entityType, entityId, action },
      },
      mutate: async (client, nextVersion) => {
        const current = await this.readSnapshot(
          entityType,
          entityId,
          this.clientRunner(client),
          true,
        );
        await this.assertBranchScope(actor, entityType, current.branch_id);
        this.assertExpectedVersion(entityType, current, dto.expectedVersion);
        if (current.lifecycle_state !== "active") {
          throw new ConflictException({
            code: "REFERENCE_ALREADY_ARCHIVED",
            message: this.archivePastMessage(entityType),
          });
        }
        this.assertNoArchiveBlockers(entityType, current);
        await this.updateLifecycle(client, entityType, entityId, {
          expectedVersion: dto.expectedVersion,
          nextVersion,
          lifecycleState: "archived",
          actorUserId: actor.userId,
          reasonText: dto.reasonText.trim(),
        });
        await this.appendHistory(client, {
          entityType,
          entityId,
          operation: entityType === "branch_discipline" ? "unassign" : "archive",
          fromState: "active",
          toState: "archived",
          version: nextVersion,
          reasonText: dto.reasonText.trim(),
          actorUserId: actor.userId,
          requestId: metadata.requestId,
          snapshot: {
            ...this.auditRef(entityType, current),
            impact: this.impact(entityType, current),
          },
        });
        const after: MutationResultRef = {
          entityType,
          entityId,
          lifecycleState: "archived",
          entityVersion: nextVersion,
        };
        audit.beforeRef = this.auditRef(entityType, current);
        audit.afterRef = after;
        return after;
      },
    });
    return {
      preview: await this.preview(actor, entityType, entityId),
      replayed: result.replayed,
    };
  }

  async restore(
    actor: ActorContext,
    entityType: ReferenceCatalogEntityType,
    entityId: string,
    dto: ReferenceCatalogLifecycleCommandDto,
    metadata: MutationMetadata,
  ) {
    this.assertCanManage(actor);
    this.assertCommand(dto, metadata);
    const initial = await this.readSnapshot(
      entityType,
      entityId,
      (query, params) => this.database.query(query, params),
    );
    await this.assertBranchScope(actor, entityType, initial.branch_id);
    this.assertExpectedVersion(entityType, initial, dto.expectedVersion);
    if (initial.lifecycle_state !== "archived") {
      throw new ConflictException({
        code: "REFERENCE_NOT_ARCHIVED",
        message: "Запись уже активна.",
      });
    }
    this.assertNoRestoreBlockers(entityType, initial);
    await this.ensureAggregateVersion(entityType, entityId, initial.version);

    const audit = this.auditInput(
      actor,
      entityType,
      initial,
      "restored",
      dto.reasonText,
    );
    const result = await this.integrity.executeVersionedMutation<MutationResultRef>({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "config.crm.edit" },
      operation: `crm.reference.${entityType}.restore`,
      idempotencyKey: metadata.idempotencyKey,
      requestId: metadata.requestId,
      aggregateType: this.aggregateType(entityType),
      aggregateId: entityId,
      expectedVersion: dto.expectedVersion,
      payload: {
        entityType,
        entityId,
        expectedVersion: dto.expectedVersion,
        reasonText: dto.reasonText.trim(),
      },
      audit,
      outbox: {
        type: "reference.catalog.changed",
        payload: { entityType, entityId, action: "restored" },
      },
      mutate: async (client, nextVersion) => {
        const current = await this.readSnapshot(
          entityType,
          entityId,
          this.clientRunner(client),
          true,
        );
        await this.assertBranchScope(actor, entityType, current.branch_id);
        this.assertExpectedVersion(entityType, current, dto.expectedVersion);
        if (current.lifecycle_state !== "archived") {
          throw new ConflictException({
            code: "REFERENCE_NOT_ARCHIVED",
            message: "Запись уже активна.",
          });
        }
        this.assertNoRestoreBlockers(entityType, current);
        await this.updateLifecycle(client, entityType, entityId, {
          expectedVersion: dto.expectedVersion,
          nextVersion,
          lifecycleState: "active",
          actorUserId: actor.userId,
          reasonText: dto.reasonText.trim(),
        });
        await this.appendHistory(client, {
          entityType,
          entityId,
          operation: "restore",
          fromState: "archived",
          toState: "active",
          version: nextVersion,
          reasonText: dto.reasonText.trim(),
          actorUserId: actor.userId,
          requestId: metadata.requestId,
          snapshot: this.auditRef(entityType, current),
        });
        const after: MutationResultRef = {
          entityType,
          entityId,
          lifecycleState: "active",
          entityVersion: nextVersion,
        };
        audit.beforeRef = this.auditRef(entityType, current);
        audit.afterRef = after;
        return after;
      },
    });
    return {
      preview: await this.preview(actor, entityType, entityId),
      replayed: result.replayed,
    };
  }

  private async readSnapshot(
    entityType: ReferenceCatalogEntityType,
    entityId: string,
    query: QueryRunner,
    lock = false,
  ): Promise<ReferenceSnapshot> {
    const sql = entityType === "discipline"
      ? `select target.id, target.name, null::text as kind,
          null::integer as sort_order, null::text as color,
          null::uuid as branch_id, null::text as branch_name,
          null::text as branch_lifecycle_state,
          null::uuid as discipline_id, null::text as discipline_lifecycle_state,
          target.lifecycle_state, target.version, target.archived_at,
          target.archive_reason,
          (select count(*) from app.branch_disciplines item
            where item.discipline_id = target.id and item.deleted_at is null) as active_branch_assignments,
          (select count(*) from app.teacher_disciplines item
            join app.teachers teacher on teacher.id = item.teacher_id
            where item.discipline_id = target.id and teacher.deleted_at is null
              and teacher.lifecycle_state = 'active') as active_teacher_assignments,
          (select count(*) from app.student_disciplines item
            join app.students student on student.id = item.student_id
            where item.discipline_id = target.id and item.deleted_at is null
              and student.deleted_at is null) as active_student_assignments,
          (select count(*) from app.subscription_packages item
            where item.discipline_id = target.id and item.deleted_at is null
              and item.is_active) as active_packages,
          (select count(*) from app.branch_disciplines item
            where item.discipline_id = target.id) as historical_branch_assignments,
          (select count(*) from app.teacher_disciplines item
            where item.discipline_id = target.id) as historical_teacher_assignments,
          (select count(*) from app.student_disciplines item
            where item.discipline_id = target.id) as historical_student_assignments,
          (select count(*) from app.subscription_package_versions item
            where item.discipline_id = target.id) as historical_packages,
          0::bigint as historical_uses
         from app.disciplines target
         where target.id = $1 ${lock ? "for update of target" : ""}`
      : entityType === "loss_reason"
        ? `select target.id, target.name, target.kind,
            target.sort_order, target.color,
            null::uuid as branch_id, null::text as branch_name,
            null::text as branch_lifecycle_state,
            null::uuid as discipline_id, null::text as discipline_lifecycle_state,
            target.lifecycle_state, target.version, target.archived_at,
            target.archive_reason,
            0::bigint as active_branch_assignments,
            0::bigint as active_teacher_assignments,
            0::bigint as active_student_assignments,
            0::bigint as active_packages,
            0::bigint as historical_branch_assignments,
            0::bigint as historical_teacher_assignments,
            0::bigint as historical_student_assignments,
            0::bigint as historical_packages,
            (select count(*) from app.lead_status_history item
              where item.reason_id = target.id) as historical_uses
           from app.lead_loss_reasons target
           where target.id = $1 ${lock ? "for update of target" : ""}`
        : `select target.id, discipline.name,
            null::text as kind, target.sort_order, null::text as color,
            target.branch_id, branch.name as branch_name,
            branch.lifecycle_state as branch_lifecycle_state,
            target.discipline_id,
            discipline.lifecycle_state as discipline_lifecycle_state,
            target.lifecycle_state, target.version, target.archived_at,
            target.archive_reason,
            0::bigint as active_branch_assignments,
            (select count(distinct td.teacher_id)
             from app.teacher_disciplines td
             join app.teacher_branches tb on tb.teacher_id = td.teacher_id
             join app.teachers teacher on teacher.id = td.teacher_id
             where td.discipline_id = target.discipline_id
               and tb.branch_id = target.branch_id
               and (tb.active_until is null or tb.active_until >= current_date)
               and teacher.deleted_at is null and teacher.lifecycle_state = 'active')
              as active_teacher_assignments,
            (select count(*)
             from app.student_disciplines sd
             join app.students student on student.id = sd.student_id
             where sd.discipline_id = target.discipline_id
               and student.branch_id = target.branch_id
               and sd.deleted_at is null and student.deleted_at is null)
              as active_student_assignments,
            (select count(*) from app.subscription_packages package
             where package.discipline_id = target.discipline_id
               and package.branch_id = target.branch_id
               and package.deleted_at is null and package.is_active) as active_packages,
            0::bigint as historical_branch_assignments,
            0::bigint as historical_teacher_assignments,
            0::bigint as historical_student_assignments,
            (select count(*) from app.subscription_package_versions package
             where package.discipline_id = target.discipline_id
               and package.branch_id = target.branch_id) as historical_packages,
            0::bigint as historical_uses
           from app.branch_disciplines target
           join app.branches branch on branch.id = target.branch_id
           join app.disciplines discipline on discipline.id = target.discipline_id
           where target.id = $1 ${lock ? "for update of target" : ""}`;
    const result = await query<ReferenceSnapshot>(sql, [entityId]);
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Запись справочника не найдена.");
    return row;
  }

  private toPreview(
    entityType: ReferenceCatalogEntityType,
    row: ReferenceSnapshot,
  ) {
    const archived = row.lifecycle_state === "archived";
    const blockers = archived
      ? this.restoreBlockers(entityType, row)
      : this.archiveBlockers(entityType, row);
    return {
      entity: this.lifecycleDto(entityType, row),
      impact: this.impact(entityType, row),
      blockers,
      canArchive: !archived && blockers.length === 0,
      canRestore: archived && blockers.length === 0,
      canRename: entityType !== "branch_discipline",
      confirmRequired: true,
      policy: {
        deletionMode: entityType === "branch_discipline" ? "unassign" : "archive",
        identityPreserved: true,
        historicalFactsPreserved: true,
      },
    };
  }

  private lifecycleDto(
    entityType: ReferenceCatalogEntityType,
    row: ReferenceSnapshot,
  ) {
    return {
      id: row.id,
      entityType,
      name: row.name,
      kind: row.kind,
      sortOrder: row.sort_order === null ? null : Number(row.sort_order),
      color: row.color,
      branchId: row.branch_id,
      branchName: row.branch_name,
      disciplineId: row.discipline_id,
      lifecycleState: row.lifecycle_state,
      version: Number(row.version),
      archivedAt: row.archived_at,
      archiveReason: row.archive_reason,
    };
  }

  private impact(entityType: ReferenceCatalogEntityType, row: ReferenceSnapshot) {
    if (entityType === "loss_reason") {
      return { historicalLeadTransitions: Number(row.historical_uses) };
    }
    if (entityType === "branch_discipline") {
      return {
        activeTeachers: Number(row.active_teacher_assignments),
        activeStudents: Number(row.active_student_assignments),
        activePackages: Number(row.active_packages),
        historicalPackages: Number(row.historical_packages),
      };
    }
    return {
      activeBranchAssignments: Number(row.active_branch_assignments),
      activeTeachers: Number(row.active_teacher_assignments),
      activeStudents: Number(row.active_student_assignments),
      activePackages: Number(row.active_packages),
      preservedHistory: {
        branchAssignments: Number(row.historical_branch_assignments),
        teacherAssignments: Number(row.historical_teacher_assignments),
        studentAssignments: Number(row.historical_student_assignments),
        packageVersions: Number(row.historical_packages),
      },
    };
  }

  private archiveBlockers(
    _entityType: ReferenceCatalogEntityType,
    _row: ReferenceSnapshot,
  ) {
    // Disciplines and branch discipline assignments are descriptive metadata.
    // Existing links stay visible in impact/history but never block archive or
    // unassignment. New selectors simply stop offering an archived value.
    return [];
  }

  private restoreBlockers(
    entityType: ReferenceCatalogEntityType,
    row: ReferenceSnapshot,
  ) {
    if (entityType !== "branch_discipline") return [];
    const blockers: Array<{
      code: string;
      label: string;
      count: number;
      remediation: string;
    }> = [];
    if (row.branch_lifecycle_state !== "active") {
      blockers.push({
        code: "PARENT_BRANCH_NOT_ACTIVE",
        label: "Филиал находится в архиве",
        count: 1,
        remediation: "Сначала восстановите филиал.",
      });
    }
    if (row.discipline_lifecycle_state !== "active") {
      blockers.push({
        code: "PARENT_DISCIPLINE_NOT_ACTIVE",
        label: "Дисциплина находится в архиве",
        count: 1,
        remediation: "Сначала восстановите дисциплину.",
      });
    }
    return blockers;
  }

  private assertNoArchiveBlockers(
    entityType: ReferenceCatalogEntityType,
    row: ReferenceSnapshot,
  ) {
    const blockers = this.archiveBlockers(entityType, row);
    if (blockers.length > 0) {
      throw new UnprocessableEntityException({
        code: entityType === "branch_discipline"
          ? "BRANCH_DISCIPLINE_UNASSIGN_BLOCKED"
          : "REFERENCE_ARCHIVE_BLOCKED",
        message: "Сначала устраните активные связи справочника.",
        blockers,
      });
    }
  }

  private assertNoRestoreBlockers(
    entityType: ReferenceCatalogEntityType,
    row: ReferenceSnapshot,
  ) {
    const blockers = this.restoreBlockers(entityType, row);
    if (blockers.length > 0) {
      throw new UnprocessableEntityException({
        code: "REFERENCE_RESTORE_BLOCKED",
        message: "Сначала восстановите родительские записи.",
        blockers,
      });
    }
  }

  private async updateLifecycle(
    client: PoolClient,
    entityType: ReferenceCatalogEntityType,
    entityId: string,
    input: {
      expectedVersion: number;
      nextVersion: number;
      lifecycleState: "active" | "archived";
      actorUserId: string;
      reasonText: string;
    },
  ) {
    const table = entityType === "discipline"
      ? "disciplines"
      : entityType === "loss_reason"
        ? "lead_loss_reasons"
        : "branch_disciplines";
    const activeColumns = entityType === "branch_discipline"
      ? ""
      : `is_active = ${input.lifecycleState === "active" ? "true" : "false"},`;
    const lifecycleColumns = input.lifecycleState === "active"
      ? `deleted_at = null, archived_at = null, archived_by = null,
         archive_reason = null,`
      : `deleted_at = now(), archived_at = now(), archived_by = $4,
         archive_reason = $5,`;
    const result = await client.query(
      `update app.${table}
       set lifecycle_state = $3,
           ${activeColumns}
           ${lifecycleColumns}
           version = $6,
           updated_at = now()
       where id = $1 and version = $2
       returning id`,
      [
        entityId,
        input.expectedVersion,
        input.lifecycleState,
        input.actorUserId,
        input.reasonText,
        input.nextVersion,
      ],
    );
    if (!result.rows[0]) {
      throw new ConflictException({
        code: "STALE_REFERENCE_VERSION",
        message: "Справочник уже изменён в другой вкладке.",
      });
    }
  }

  private async assertNameAvailable(
    client: PoolClient,
    entityType: "discipline" | "loss_reason",
    entityId: string,
    name: string,
    kind: string | null,
  ) {
    const table = entityType === "discipline" ? "disciplines" : "lead_loss_reasons";
    const result = await client.query(
      `select id from app.${table}
       where id <> $1 and lower(btrim(name)) = lower(btrim($2))
         ${entityType === "loss_reason" ? "and kind = $3" : ""}
       limit 1`,
      entityType === "loss_reason" ? [entityId, name, kind] : [entityId, name],
    );
    if (result.rows[0]) {
      throw new ConflictException({
        code: "REFERENCE_NAME_CONFLICT",
        message: "Запись с таким названием уже существует, включая архив.",
      });
    }
  }

  private assertCanManage(actor: ActorContext) {
    this.policy.assertCanManageClientConfiguration(actor);
  }

  private assertCommand(
    dto: ReferenceCatalogLifecycleCommandDto,
    metadata: MutationMetadata,
  ) {
    if (dto.confirm !== true) {
      throw new UnprocessableEntityException({
        code: "REFERENCE_CONFIRMATION_REQUIRED",
        message: "Подтвердите действие после просмотра последствий.",
      });
    }
    if (!Number.isSafeInteger(dto.expectedVersion) || dto.expectedVersion < 1) {
      throw new UnprocessableEntityException({
        code: "REFERENCE_VERSION_REQUIRED",
        message: "Передайте актуальную версию справочника.",
      });
    }
    if (!dto.reasonText.trim()) {
      throw new UnprocessableEntityException({
        code: "REFERENCE_REASON_REQUIRED",
        message: "Укажите причину изменения.",
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
    entityType: ReferenceCatalogEntityType,
    row: ReferenceSnapshot,
    expectedVersion: number,
  ) {
    if (Number(row.version) !== expectedVersion) {
      this.throwStale(entityType, expectedVersion, row);
    }
  }

  private throwStale(
    entityType: ReferenceCatalogEntityType,
    expectedVersion: number,
    row: ReferenceSnapshot,
  ): never {
    throw new ConflictException({
      code: "STALE_REFERENCE_VERSION",
      message: "Справочник уже изменён в другой вкладке.",
      entityType,
      expectedVersion,
      currentVersion: Number(row.version),
    });
  }

  private async assertBranchScope(
    actor: ActorContext,
    entityType: ReferenceCatalogEntityType,
    branchId: string | null,
  ) {
    if (entityType === "branch_discipline" && branchId) {
      await assertSettingsBranchScope(this.database, actor, branchId);
    }
  }

  private ensureAggregateVersion(
    entityType: ReferenceCatalogEntityType,
    entityId: string,
    version: number | string,
  ) {
    return this.database.query(
      `insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
       values ($1, $2, $3)
       on conflict (aggregate_type, aggregate_id) do nothing`,
      [this.aggregateType(entityType), entityId, Number(version)],
    );
  }

  private appendHistory(
    client: PoolClient,
    input: {
      entityType: ReferenceCatalogEntityType;
      entityId: string;
      operation: "rename" | "archive" | "restore" | "unassign";
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
      `insert into app.reference_catalog_history (
         entity_type, entity_id, operation, from_state, to_state, version,
         reason_text, actor_user_id, request_id, snapshot
       ) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb)`,
      [
        input.entityType,
        input.entityId,
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

  private auditInput(
    actor: ActorContext,
    entityType: ReferenceCatalogEntityType,
    snapshot: ReferenceSnapshot,
    action: string,
    reasonText: string,
  ): PlatformAuditInput {
    return {
      action: `crm.reference_${entityType}_${action}`,
      entityType,
      entityId: snapshot.id,
      reason: `reference.${entityType}.${action}`,
      reasonText: reasonText.trim(),
      beforeRef: this.auditRef(entityType, snapshot),
      metadata: { actorRole: actor.role, lifecycleAction: action },
    };
  }

  private auditRef(
    entityType: ReferenceCatalogEntityType,
    row: ReferenceSnapshot,
  ) {
    return {
      entityType,
      id: row.id,
      name: row.name,
      kind: row.kind,
      branchId: row.branch_id,
      disciplineId: row.discipline_id,
      lifecycleState: row.lifecycle_state,
      version: Number(row.version),
    };
  }

  private aggregateType(entityType: ReferenceCatalogEntityType) {
    return `reference:${entityType}`;
  }

  private clientRunner(client: PoolClient): QueryRunner {
    return <T extends QueryResultRow>(query: string, params?: unknown[]) =>
      client.query<T>(query, params);
  }

  private archivePastMessage(entityType: ReferenceCatalogEntityType) {
    return entityType === "branch_discipline"
      ? "Дисциплина уже отвязана от филиала."
      : "Запись уже находится в архиве.";
  }

  private translateUniqueViolation(error: unknown) {
    if (
      typeof error === "object" &&
      error !== null &&
      "code" in error &&
      (error as { code?: string }).code === "23505"
    ) {
      throw new ConflictException({
        code: "REFERENCE_NAME_CONFLICT",
        message: "Запись с таким названием уже существует, включая архив.",
      });
    }
  }
}
