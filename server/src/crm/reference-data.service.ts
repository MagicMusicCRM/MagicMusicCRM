import {
  ConflictException,
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CrmListQuery } from "./dto/crm-list.query";
import { CrmPolicy } from "./crm.policy";
import { HolliHopMetadataService } from "./hollihop-metadata.service";
import { requiredTrim } from "./crm-util";
import { assertSettingsBranchScope } from "./settings-branch-scope";

interface LeadStatusRow {
  id: string;
  stage_key: string;
  name: string;
  color: string | null;
  sort_order: number;
  created_at: Date | string;
  requires_reason?: boolean;
  is_terminal?: boolean;
}

/**
 * CRM reference/catalog data, extracted from CrmService (SRP): lead statuses,
 * loss reasons, lead sources, disciplines and branch-discipline links, plus the
 * HolliHop metadata proxies. Leaf domain — touches only the reference tables
 * (`app.lead_statuses`, `app.lead_loss_reasons`, `app.lead_sources`,
 * `app.disciplines`, `app.branch_disciplines`) and the shared
 * database/audit/policy/hollihop collaborators, no other CrmService internals.
 */
@Injectable()
export class ReferenceDataService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly hollihop: HolliHopMetadataService,
  ) {}

  // ponytail: LeadStatusRow + toLeadStatusDto are duplicated from CrmService, which
  // still uses them for lead-board/lead-detail flows. Fold into a shared mapper in B4/B5.
  private toLeadStatusDto(row: LeadStatusRow) {
    return {
      id: row.id,
      stageKey: row.stage_key,
      name: row.name,
      color: row.color,
      sortOrder: row.sort_order,
      createdAt: row.created_at,
      requiresReason: row.requires_reason ?? false,
      isTerminal: row.is_terminal ?? false,
    };
  }

  async listLeadStatuses(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanWriteCrm(actor);
    const limit = Math.min(query.limit ?? 100, 100);
    const result = await this.database.query<LeadStatusRow>(
      `
        select id, stage_key, name, color, sort_order, created_at, requires_reason, is_terminal
        from app.lead_statuses
        order by sort_order asc, name asc, id asc
        limit $1
      `,
      [limit],
    );

    return { items: result.rows.map((row) => this.toLeadStatusDto(row)) };
  }

  async listLossReasons(actor: ActorContext, includeArchived = false) {
    if (includeArchived) this.policy.assertCanManageClientConfiguration(actor);
    else this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      name: string;
      kind: string;
      sort_order: number;
      color: string | null;
      lifecycle_state: "active" | "archived";
      version: number | string;
      archived_at: Date | string | null;
      archive_reason: string | null;
      historical_uses: number | string;
    }>(
      `select target.id, target.name, target.kind, target.sort_order,
              target.color, target.lifecycle_state, target.version,
              target.archived_at, target.archive_reason,
              (select count(*) from app.lead_status_history history
                where history.reason_id = target.id) as historical_uses
         from app.lead_loss_reasons target
        where ($1::boolean or (
          target.lifecycle_state = 'active' and target.is_active
          and target.deleted_at is null
        ))
        order by (target.lifecycle_state = 'archived') asc,
          target.sort_order asc, target.name asc`,
      [includeArchived],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        name: row.name,
        kind: row.kind,
        sortOrder: row.sort_order,
        color: row.color,
        lifecycleState: row.lifecycle_state,
        version: Number(row.version),
        archivedAt: row.archived_at,
        archiveReason: row.archive_reason,
        historicalUses: Number(row.historical_uses),
      })),
    };
  }

  async listLeadSources(actor: ActorContext) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      canonical_name: string;
      display_name: string;
    }>(
      `select id, canonical_name, display_name
         from app.lead_sources
        where is_active and deleted_at is null
        order by display_name asc`,
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        canonicalName: row.canonical_name,
        displayName: row.display_name,
      })),
    };
  }

  async listDisciplines(actor: ActorContext, includeArchived = false) {
    if (includeArchived) this.policy.assertCanManageClientConfiguration(actor);
    else this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      name: string;
      lifecycle_state: "active" | "archived";
      version: number | string;
      archived_at: Date | string | null;
      archive_reason: string | null;
      active_branch_assignments: number | string;
      active_teacher_assignments: number | string;
      active_student_assignments: number | string;
      active_packages: number | string;
    }>(
      `select target.id, target.name, target.lifecycle_state, target.version,
              target.archived_at, target.archive_reason,
              (select count(*) from app.branch_disciplines item
                where item.discipline_id = target.id and item.deleted_at is null)
                as active_branch_assignments,
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
                  and item.is_active) as active_packages
         from app.disciplines target
        where ($1::boolean or (
          target.lifecycle_state = 'active' and target.is_active
          and target.deleted_at is null
        ))
        order by (target.lifecycle_state = 'archived') asc, target.name asc`,
      [includeArchived],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        name: row.name,
        lifecycleState: row.lifecycle_state,
        version: Number(row.version),
        archivedAt: row.archived_at,
        archiveReason: row.archive_reason,
        activeUsage: {
          branchAssignments: Number(row.active_branch_assignments),
          teachers: Number(row.active_teacher_assignments),
          students: Number(row.active_student_assignments),
          packages: Number(row.active_packages),
        },
      })),
    };
  }

  async listBranchDisciplines(
    actor: ActorContext,
    branchId: string,
    includeArchived = false,
  ) {
    if (includeArchived) this.policy.assertCanManageClientConfiguration(actor);
    else this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      discipline_id: string;
      name: string;
      sort_order: number;
      lifecycle_state: "active" | "archived";
      version: number | string;
      archived_at: Date | string | null;
      archive_reason: string | null;
    }>(
      `select bd.id, bd.discipline_id, d.name, bd.sort_order,
              bd.lifecycle_state, bd.version, bd.archived_at, bd.archive_reason
         from app.branch_disciplines bd
         join app.disciplines d on d.id = bd.discipline_id
        where bd.branch_id = $1
          and ($2::boolean or (
            bd.lifecycle_state = 'active' and bd.deleted_at is null
            and d.lifecycle_state = 'active' and d.deleted_at is null and d.is_active
          ))
        order by (bd.lifecycle_state = 'archived') asc,
          bd.sort_order asc, d.name asc`,
      [branchId, includeArchived],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        disciplineId: row.discipline_id,
        name: row.name,
        sortOrder: row.sort_order,
        lifecycleState: row.lifecycle_state,
        version: Number(row.version),
        archivedAt: row.archived_at,
        archiveReason: row.archive_reason,
      })),
    };
  }

  async listHolliHopDisciplines(actor: ActorContext) {
    this.policy.assertCanWriteCrm(actor);
    return this.hollihop.listDisciplines();
  }

  async listHolliHopLevels(actor: ActorContext) {
    this.policy.assertCanWriteCrm(actor);
    return this.hollihop.listLevels();
  }

  async listHolliHopCategories(actor: ActorContext) {
    this.policy.assertCanWriteCrm(actor);
    return this.hollihop.listCategories();
  }

  async listHolliHopLeadStatuses(actor: ActorContext) {
    this.policy.assertCanWriteCrm(actor);
    return this.hollihop.listLeadStatuses();
  }

  async createDiscipline(actor: ActorContext, dto: { name: string }) {
    this.policy.assertCanManageClientConfiguration(actor);
    const name = requiredTrim(dto.name, "Название дисциплины обязательно.");
    const result = await this.database.query<{
      id: string;
      name: string;
      lifecycle_state: "active";
      version: number | string;
    }>(
      `insert into app.disciplines (name)
       values ($1)
       returning id, name, lifecycle_state, version`,
      [name],
    );
    return {
      id: result.rows[0].id,
      name: result.rows[0].name,
      lifecycleState: result.rows[0].lifecycle_state,
      version: Number(result.rows[0].version),
    };
  }

  async createLossReason(
    actor: ActorContext,
    dto: { name: string; kind?: "lost" | "paused"; sortOrder?: number },
  ) {
    this.policy.assertCanManageClientConfiguration(actor);
    const name = requiredTrim(dto.name, "Название причины обязательно.");
    const result = await this.database.query<{
      id: string;
      name: string;
      kind: string;
      sort_order: number;
      lifecycle_state: "active";
      version: number | string;
    }>(
      `insert into app.lead_loss_reasons (name, kind, sort_order)
       values ($1, $2, $3)
       returning id, name, kind, sort_order, lifecycle_state, version`,
      [name, dto.kind ?? "lost", dto.sortOrder ?? 0],
    );
    const row = result.rows[0];
    return {
      id: row.id,
      name: row.name,
      kind: row.kind,
      sortOrder: row.sort_order,
      lifecycleState: row.lifecycle_state,
      version: Number(row.version),
    };
  }

  async assignBranchDiscipline(
    actor: ActorContext,
    branchId: string,
    dto: { disciplineId: string; sortOrder?: number },
  ) {
    this.policy.assertCanManageClientConfiguration(actor);
    await assertSettingsBranchScope(this.database, actor, branchId);
    const result = await this.database.query<{
      id: string;
      discipline_id: string;
      sort_order: number;
      lifecycle_state: "active";
      version: number | string;
    }>(
      `insert into app.branch_disciplines (
         branch_id, discipline_id, sort_order
       )
       select $1, $2,
         coalesce($3, (select coalesce(max(sort_order) + 1, 0)
                         from app.branch_disciplines
                        where branch_id = $1 and deleted_at is null))
       from app.branches branch
       join app.disciplines discipline on discipline.id = $2
       where branch.id = $1
         and branch.lifecycle_state = 'active' and branch.deleted_at is null
         and discipline.lifecycle_state = 'active'
         and discipline.is_active and discipline.deleted_at is null
       on conflict (branch_id, discipline_id)
       do update set
         sort_order = coalesce($3, app.branch_disciplines.sort_order),
         updated_at = now()
       where app.branch_disciplines.lifecycle_state = 'active'
         and app.branch_disciplines.deleted_at is null
       returning id, discipline_id, sort_order, lifecycle_state, version`,
      [branchId, dto.disciplineId, dto.sortOrder ?? null],
    );
    const row = result.rows[0];
    if (!row) {
      const existing = await this.database.query<{
        lifecycle_state: "active" | "archived";
      }>(
        `select lifecycle_state from app.branch_disciplines
         where branch_id = $1 and discipline_id = $2`,
        [branchId, dto.disciplineId],
      );
      if (existing.rows[0]?.lifecycle_state === "archived") {
        throw new ConflictException({
          code: "BRANCH_DISCIPLINE_RESTORE_REQUIRED",
          message: "Привязка находится в архиве. Используйте восстановление.",
        });
      }
      throw new UnprocessableEntityException({
        code: "BRANCH_DISCIPLINE_PARENT_INACTIVE",
        message: "Филиал или дисциплина недоступны для назначения.",
      });
    }
    return {
      id: row.id,
      disciplineId: row.discipline_id,
      sortOrder: row.sort_order,
      lifecycleState: row.lifecycle_state,
      version: Number(row.version),
    };
  }

  async reorderBranchDisciplines(
    actor: ActorContext,
    branchId: string,
    dto: { disciplineIds: string[] },
  ) {
    this.policy.assertCanManageClientConfiguration(actor);
    await assertSettingsBranchScope(this.database, actor, branchId);
    const result = await this.database.query(
      `update app.branch_disciplines bd
          set sort_order = t.ord - 1
         from unnest($2::uuid[]) with ordinality as t(discipline_id, ord)
        where bd.branch_id = $1
          and bd.discipline_id = t.discipline_id
          and bd.deleted_at is null`,
      [branchId, dto.disciplineIds],
    );
    return { updated: result.rowCount ?? 0 };
  }
}
