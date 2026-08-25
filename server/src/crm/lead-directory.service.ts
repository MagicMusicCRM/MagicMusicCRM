import { Injectable } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { CrmListQuery } from "./dto/crm-list.query";
import { LeadRow, toLeadDto } from "./lead-model";
import { buildTextSearch } from "./search-text";

@Injectable()
export class LeadDirectoryService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
  ) {}

  async list(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanWriteCrm(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const q = query.q?.trim();
    const params: unknown[] = [];
    const add = (value: unknown) => {
      params.push(value);
      return `$${params.length}`;
    };
    const search = q
      ? buildTextSearch({
          q,
          columns: [
            "l.first_name",
            "l.last_name",
            "l.email",
            "l.phone",
            "l.source",
          ],
          phoneColumn: "l.phone",
          customDataColumn: "l.custom_data",
          exactColumn: "concat_ws(' ', l.first_name, l.last_name)",
          add,
        })
      : null;
    const limitParam = add(limit);
    const result = await this.database.query<LeadRow>(
      `
        select l.id, l.status_id, ls.stage_key as status_key,
          ls.name as status_name, l.first_name,
          l.last_name, l.phone, l.email, l.source, l.notes, l.assigned_to, l.blacklisted, l.blacklist_reason, l.custom_data,
          l.created_by, l.created_at, l.updated_at
        from app.leads l
        left join app.lead_statuses ls on ls.id = l.status_id
        where l.deleted_at is null
          ${search ? `and ${search.where}` : ""}
        order by ${search ? `${search.rank} asc,` : ""} l.created_at desc, l.id desc
        limit ${limitParam}
      `,
      params,
    );
    return { items: result.rows.map(toLeadDto) };
  }

  async listStatusHistory(actor: ActorContext, leadId: string) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      old_status: string | null;
      new_status: string | null;
      old_owner_id: string | null;
      new_owner_id: string | null;
      changed_by: string | null;
      changed_by_name: string | null;
      changed_at: string;
      reason_id: string | null;
      reason_name_snapshot: string | null;
      reason_kind_snapshot: string | null;
      comment: string | null;
    }>(
      `select h.id,
              os.name as old_status,
              ns.name as new_status,
              h.old_owner_id, h.new_owner_id, h.changed_by, h.changed_at,
              h.reason_id, h.reason_name_snapshot, h.reason_kind_snapshot,
              h.comment,
              nullif(trim(coalesce(cp.first_name, '') || ' ' || coalesce(cp.last_name, '')), '') as changed_by_name
         from app.lead_status_history h
         left join app.lead_statuses os on os.id = h.old_status_id
         left join app.lead_statuses ns on ns.id = h.new_status_id
         left join app.users cu on cu.id = h.changed_by and cu.deleted_at is null
         left join app.profiles cp on cp.user_id = cu.id and cp.deleted_at is null
        where h.lead_id = $1
        order by h.changed_at desc`,
      [leadId],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        oldStatus: row.old_status,
        newStatus: row.new_status,
        oldOwnerId: row.old_owner_id,
        newOwnerId: row.new_owner_id,
        changedBy: row.changed_by,
        changedByName: row.changed_by_name,
        changedAt: row.changed_at,
        reasonId: row.reason_id,
        reasonName: row.reason_name_snapshot,
        reasonKind: row.reason_kind_snapshot,
        comment: row.comment,
      })),
    };
  }

  async listApplications(actor: ActorContext, leadId: string) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      applied_at: string;
      channel: string | null;
      office: string | null;
      discipline: string | null;
      status: string | null;
      utm: Record<string, unknown> | null;
    }>(
      `select id, applied_at, channel, office, discipline, status, utm
         from app.lead_applications
        where lead_id = $1 and deleted_at is null
        order by applied_at desc`,
      [leadId],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        appliedAt: row.applied_at,
        channel: row.channel,
        office: row.office,
        discipline: row.discipline,
        status: row.status,
        utm: row.utm,
      })),
    };
  }
}
