import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CrmListQuery } from "./dto/crm-list.query";
import { UpsertLeadStatusDto } from "./dto/upsert-lead-status.dto";
import { CrmPolicy } from "./crm.policy";
import { HolliHopMetadataService } from "./hollihop-metadata.service";

interface LeadStatusRow {
  id: string;
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
        select id, name, color, sort_order, created_at, requires_reason, is_terminal
        from app.lead_statuses
        order by sort_order asc, name asc, id asc
        limit $1
      `,
      [limit],
    );

    return { items: result.rows.map((row) => this.toLeadStatusDto(row)) };
  }

  async listLossReasons(actor: ActorContext) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      name: string;
      kind: string;
      sort_order: number;
      color: string | null;
    }>(
      `select id, name, kind, sort_order, color
         from app.lead_loss_reasons
        where is_active and deleted_at is null
        order by sort_order asc, name asc`,
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        name: row.name,
        kind: row.kind,
        sortOrder: row.sort_order,
        color: row.color,
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

  async listDisciplines(actor: ActorContext) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{ id: string; name: string }>(
      `select id, name
         from app.disciplines
        where is_active and deleted_at is null
        order by name asc`,
    );
    return { items: result.rows.map((row) => ({ id: row.id, name: row.name })) };
  }

  async listBranchDisciplines(actor: ActorContext, branchId: string) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      discipline_id: string;
      name: string;
      sort_order: number;
    }>(
      `select bd.id, bd.discipline_id, d.name, bd.sort_order
         from app.branch_disciplines bd
         join app.disciplines d on d.id = bd.discipline_id and d.deleted_at is null and d.is_active
        where bd.branch_id = $1 and bd.deleted_at is null
        order by bd.sort_order asc, d.name asc`,
      [branchId],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        disciplineId: row.discipline_id,
        name: row.name,
        sortOrder: row.sort_order,
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

  async createLeadStatus(actor: ActorContext, dto: UpsertLeadStatusDto) {
    this.policy.assertCanWriteCrm(actor);
    const label = dto.label.trim();
    if (!label) throw new BadRequestException("Название статуса обязательно.");
    const result = await this.database.query<LeadStatusRow>(
      `
        insert into app.lead_statuses (name, color, sort_order)
        values ($1, $2, coalesce($3, 0))
        returning id, name, color, sort_order, created_at
      `,
      [label, dto.color?.trim() || null, dto.sortOrder ?? null],
    );
    const status = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.lead_status_created",
      entityType: "lead",
      entityId: status.id,
      metadata: { key: dto.key?.trim() || null },
    });
    return this.toLeadStatusDto(status);
  }

  async deleteLeadStatus(actor: ActorContext, statusId: string) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string }>(
      `
        delete from app.lead_statuses
        where id = $1
        returning id
      `,
      [statusId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Статус лида не найден.");
    await this.audit.record({
      actor,
      action: "crm.lead_status_deleted",
      entityType: "lead",
      entityId: row.id,
    });
    return { success: true };
  }

  async reorderLeadStatuses(actor: ActorContext, dto: { statusIds: string[] }) {
    this.policy.assertCanWriteCrm(actor);
    const statusIds = Array.isArray(dto.statusIds) ? dto.statusIds : [];
    if (statusIds.length === 0) {
      throw new BadRequestException("Список статусов воронки пуст.");
    }
    const result = await this.database.query(
      `update app.lead_statuses ls
          set sort_order = t.ord - 1
         from unnest($1::uuid[]) with ordinality as t(status_id, ord)
        where ls.id = t.status_id`,
      [statusIds],
    );
    await this.audit.record({
      actor,
      action: "crm.lead_statuses_reordered",
      entityType: "lead",
      metadata: { order: statusIds },
    });
    return { updated: result.rowCount ?? 0 };
  }

  async createDiscipline(actor: ActorContext, dto: { name: string }) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string; name: string }>(
      `insert into app.disciplines (name) values ($1) returning id, name`,
      [dto.name],
    );
    return { id: result.rows[0].id, name: result.rows[0].name };
  }

  async createLossReason(
    actor: ActorContext,
    dto: { name: string; kind?: "lost" | "paused"; sortOrder?: number },
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      name: string;
      kind: string;
      sort_order: number;
    }>(
      `insert into app.lead_loss_reasons (name, kind, sort_order)
       values ($1, $2, $3)
       returning id, name, kind, sort_order`,
      [dto.name, dto.kind ?? "lost", dto.sortOrder ?? 0],
    );
    const row = result.rows[0];
    return { id: row.id, name: row.name, kind: row.kind, sortOrder: row.sort_order };
  }

  async assignBranchDiscipline(
    actor: ActorContext,
    branchId: string,
    dto: { disciplineId: string; sortOrder?: number },
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      discipline_id: string;
      sort_order: number;
    }>(
      `insert into app.branch_disciplines (branch_id, discipline_id, sort_order)
       values (
         $1, $2,
         coalesce($3, (select coalesce(max(sort_order) + 1, 0)
                         from app.branch_disciplines
                        where branch_id = $1 and deleted_at is null))
       )
       on conflict (branch_id, discipline_id)
       do update set sort_order = coalesce($3, app.branch_disciplines.sort_order), deleted_at = null
       returning id, discipline_id, sort_order`,
      [branchId, dto.disciplineId, dto.sortOrder ?? null],
    );
    const row = result.rows[0];
    return { id: row.id, disciplineId: row.discipline_id, sortOrder: row.sort_order };
  }

  async reorderBranchDisciplines(
    actor: ActorContext,
    branchId: string,
    dto: { disciplineIds: string[] },
  ) {
    this.policy.assertCanWriteCrm(actor);
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
