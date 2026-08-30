import {
  ConflictException,
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import { PoolClient } from "pg";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import {
  replaceTypedClientValues,
  saveTypedClientValues,
} from "./clients/client-config.repository";
import {
  ValidatedCustomFields,
  ValidatedLeadCreate,
} from "./clients/client-write.validator";
import { sanitizeJsonObject } from "./crm-util";
import { UpdateLeadDto, UpsertLeadDto } from "./dto/upsert-lead.dto";
import { extractBranchId } from "./branch-scope";
import { LeadRow } from "./lead-model";
import {
  applyEligibleResponsibleToCustomData,
  assertEligibleResponsible,
} from "./responsible-eligibility";
import { StudentFunnelService } from "./student-funnel.service";

export interface LeadWriteResult {
  before: (LeadRow & { branch_id: string | null }) | null;
  lead: LeadRow | null;
  branchId: string | null;
}

@Injectable()
export class LeadWriteRepository {
  constructor(
    private readonly database: DatabaseService,
    private readonly pipelines: StudentFunnelService,
  ) {}

  async create(
    actor: ActorContext,
    dto: UpsertLeadDto,
    validated?: ValidatedLeadCreate,
  ) {
    const branchId = extractBranchId(dto.customDataPatch);
    const statusId = await this.resolveStatusId(dto.statusId);
    const initialCustomData = sanitizeJsonObject(dto.customDataPatch);
    const lead = await this.database.transaction(async (client) => {
      await this.assertInitialTransition(client, branchId, statusId);
      const customData = await this.prepareCustomData(
        client,
        dto,
        initialCustomData,
        true,
      );
      const inserted = await this.insertLead(
        client,
        actor,
        dto,
        validated,
        branchId,
        statusId,
        customData,
      );
      if (validated) {
        await saveTypedClientValues(
          client,
          "lead",
          inserted.id,
          validated.customFields,
        );
      }
      return inserted;
    });
    return { lead, branchId };
  }

  async update(
    actor: ActorContext,
    leadId: string,
    dto: UpdateLeadDto,
    customFields?: ValidatedCustomFields,
  ): Promise<LeadWriteResult> {
    const branchId = extractBranchId(dto.customDataPatch);
    const statusId = await this.resolveStatusId(dto.statusId);
    const initialCustomData = sanitizeJsonObject(dto.customDataPatch);
    return this.database.transaction(async (client) => {
      const before = await this.lockLead(client, leadId);
      this.assertExpectedVersion(before, dto.expectedVersion);
      await this.assertUpdateTransition(
        client,
        before,
        branchId,
        statusId,
        dto,
      );
      const sourceName = await this.resolveSourceName(client, dto);
      const customData = await this.prepareCustomData(
        client,
        dto,
        initialCustomData,
        before !== null,
      );
      const lead = await this.updateRow(
        client,
        leadId,
        dto,
        branchId,
        statusId,
        sourceName,
        customData,
      );
      if (lead && customFields) {
        await replaceTypedClientValues(
          client,
          "lead",
          leadId,
          customFields.values,
        );
      }
      await this.recordHistory(client, actor, leadId, dto, branchId, before, lead);
      return { before, lead, branchId };
    });
  }

  private async resolveStatusId(raw: string | null | undefined) {
    const value = raw?.trim();
    if (!value) return null;
    const uuid =
      /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
    if (uuid.test(value)) {
      const result = await this.database.query<{ id: string }>(
        "select id from app.lead_statuses where id = $1 limit 1",
        [value],
      );
      return result.rows[0]?.id ?? null;
    }
    const result = await this.database.query<{ id: string }>(
      `select min(id::text)::uuid as id
       from app.lead_statuses
       where stage_key = $1 or lower(btrim(name)) = lower(btrim($1))
       having count(*) = 1`,
      [value],
    );
    return result.rows[0]?.id ?? null;
  }

  private async assertInitialTransition(
    client: PoolClient,
    branchId: string | null,
    statusId: string | null,
  ) {
    if (!statusId) return;
    await this.pipelines.assertLeadTransition(
      client,
      branchId,
      null,
      statusId,
    );
  }

  private async assertUpdateTransition(
    client: PoolClient,
    before: (LeadRow & { branch_id: string | null }) | null,
    branchId: string | null,
    statusId: string | null,
    dto: UpsertLeadDto,
  ) {
    if (!before || !statusId) return;
    await this.pipelines.assertLeadTransition(
      client,
      branchId ?? before.branch_id,
      before.status_id,
      statusId,
      Boolean(dto.reasonId || dto.statusComment?.trim()),
    );
  }

  private async prepareCustomData(
    client: PoolClient,
    dto: UpsertLeadDto,
    initial: Record<string, unknown>,
    validateResponsible: boolean,
  ) {
    const customData = { ...initial };
    const assignedTo = dto.clearAssignedTo ? null : (dto.assignedTo ?? null);
    if (assignedTo && validateResponsible) {
      const responsible = await assertEligibleResponsible(client, assignedTo, {
        lock: true,
      });
      return applyEligibleResponsibleToCustomData(customData, responsible);
    }
    if (dto.clearAssignedTo) {
      delete customData.responsible;
      delete customData.responsibleUserId;
      delete customData.responsibleName;
    }
    return customData;
  }

  private async insertLead(
    client: PoolClient,
    actor: ActorContext,
    dto: UpsertLeadDto,
    validated: ValidatedLeadCreate | undefined,
    branchId: string | null,
    statusId: string | null,
    customData: Record<string, unknown>,
  ) {
    const assignedTo = dto.clearAssignedTo ? null : (dto.assignedTo ?? null);
    const result = await client.query<LeadRow>(
      `
        insert into app.leads (
          status_id, first_name, last_name, phone, email,
          source, notes, assigned_to, custom_data, created_by, branch_id,
          source_id
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
        returning id, version, status_id, null::text as status_name, first_name,
          last_name, phone, email, source, source_id, notes, assigned_to,
          blacklisted, blacklist_reason, custom_data, created_by, created_at,
          updated_at
      `,
      [
        statusId,
        dto.firstName?.trim() || null,
        dto.lastName?.trim() || null,
        dto.phone?.trim() || null,
        dto.email?.trim().toLowerCase() || null,
        dto.source?.trim() || null,
        dto.notes?.trim() || null,
        assignedTo,
        customData,
        actor.userId,
        branchId,
        validated?.sourceId ?? null,
      ],
    );
    return result.rows[0]!;
  }

  private async lockLead(client: PoolClient, leadId: string) {
    const result = await client.query<LeadRow & { branch_id: string | null }>(
      `select id, version, status_id, null::text as status_name, first_name, last_name,
         phone, email, source, source_id, notes, assigned_to, custom_data,
         created_by, created_at, updated_at, branch_id
       from app.leads where id = $1 and deleted_at is null for update`,
      [leadId],
    );
    return result.rows[0] ?? null;
  }

  private assertExpectedVersion(
    before: (LeadRow & { branch_id: string | null }) | null,
    expectedVersion: number | undefined,
  ) {
    if (!before || expectedVersion === undefined) return;
    const currentVersion = Number(before.version ?? 1);
    if (currentVersion === expectedVersion) return;
    throw new ConflictException({
      code: "CLIENT_VERSION_CONFLICT",
      entityType: "lead",
      expectedVersion,
      currentVersion,
      message: "Карточку лида уже изменил другой сотрудник.",
    });
  }

  private async resolveSourceName(client: PoolClient, dto: UpsertLeadDto) {
    if (!dto.sourceId) return dto.source?.trim() || null;
    const source = await client.query<{ display_name: string }>(
      `select display_name from app.lead_sources
       where id = $1 and is_active and deleted_at is null limit 1`,
      [dto.sourceId],
    );
    const sourceName = source.rows[0]?.display_name ?? null;
    if (sourceName) return sourceName;
    throw new UnprocessableEntityException({
      code: "SOURCE_INACTIVE",
      field: "sourceId",
      message: "Выберите активный источник.",
    });
  }

  private async updateRow(
    client: PoolClient,
    leadId: string,
    dto: UpsertLeadDto,
    branchId: string | null,
    statusId: string | null,
    sourceName: string | null,
    customData: Record<string, unknown>,
  ) {
    const assignedTo = dto.clearAssignedTo ? null : (dto.assignedTo ?? null);
    const result = await client.query<LeadRow>(
      `
        update app.leads
        set status_id = case when $11::boolean then null
                             else coalesce($2, status_id) end,
          first_name = coalesce($3, first_name),
          last_name = coalesce($4, last_name),
          phone = coalesce($5, phone),
          email = case when $15::boolean then null
                       else coalesce($6, email) end,
          source = coalesce($7, source),
          source_id = coalesce($14::uuid, source_id),
          notes = coalesce($8, notes),
          assigned_to = case when $13::boolean then null
                             else coalesce($9, assigned_to) end,
          custom_data = case when $13::boolean then
              jsonb_strip_nulls(coalesce(custom_data, '{}'::jsonb) || $10::jsonb)
                - 'responsible' - 'responsibleUserId' - 'responsibleName'
            else jsonb_strip_nulls(coalesce(custom_data, '{}'::jsonb) || $10::jsonb) end,
          branch_id = coalesce($12::uuid, branch_id),
          version = version + 1,
          updated_at = now()
        where id = $1 and deleted_at is null
        returning id, version, status_id, null::text as status_name, first_name,
          last_name, phone, email, source, source_id, notes, assigned_to,
          blacklisted, blacklist_reason, custom_data, created_by, created_at,
          updated_at
      `,
      [
        leadId,
        statusId,
        dto.firstName?.trim() || null,
        dto.lastName?.trim() || null,
        dto.phone?.trim() || null,
        dto.email?.trim().toLowerCase() || null,
        sourceName,
        dto.notes?.trim() || null,
        assignedTo,
        customData,
        dto.clearStatus ?? false,
        branchId,
        dto.clearAssignedTo ?? false,
        dto.sourceId ?? null,
        dto.clearEmail ?? false,
      ],
    );
    return result.rows[0] ?? null;
  }

  private async recordHistory(
    client: PoolClient,
    actor: ActorContext,
    leadId: string,
    dto: UpsertLeadDto,
    branchId: string | null,
    before: (LeadRow & { branch_id: string | null }) | null,
    lead: LeadRow | null,
  ) {
    if (!before || !lead) return;
    const changed =
      before.status_id !== lead.status_id ||
      before.assigned_to !== lead.assigned_to;
    if (!changed) return;
    await client.query(
      `insert into app.lead_status_history
       (lead_id, old_status_id, new_status_id, old_owner_id, new_owner_id,
        changed_by, reason_id, reason_name_snapshot, reason_kind_snapshot,
        comment, branch_id, source_snapshot)
       values (
         $1, $2, $3, $4, $5, $6, $7,
         (select name from app.lead_loss_reasons where id = $7),
         (select kind from app.lead_loss_reasons where id = $7),
         $8, $9, $10
       )`,
      [
        leadId,
        before.status_id,
        lead.status_id,
        before.assigned_to,
        lead.assigned_to,
        actor.userId,
        dto.reasonId ?? null,
        dto.statusComment ?? null,
        branchId ?? before.branch_id,
        lead.source,
      ],
    );
  }
}
