import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { authorizeCurrentCapability } from "../access-control/capability-request-authorizer";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { managerAdminRolesSql } from "../common/security/role-sql";
import { CreateBranchDto } from "./dto/create-branch.dto";
import { BranchListQuery } from "./dto/branch-lifecycle.dto";
import { UpdateBranchDto } from "./dto/update-branch.dto";
import { CrmPolicy } from "./crm.policy";
import { currentActorRoleSql, managerBranchScopeSql } from "./branch-scope";
import { assertBranchHours } from "./schedule/availability.rules";
import { assertSettingsBranchScope } from "./settings-branch-scope";

interface BranchRow {
  id: string;
  name: string;
  address: string | null;
  utc_offset_minutes: number | string;
  timezone_name?: string;
  schedule_reference_version?: number | string;
  lifecycle_state?: "active" | "archived";
  version?: number | string;
  archived_at?: Date | string | null;
  archive_reason?: string | null;
  archive_effective_date?: string | null;
  created_at: Date | string;
}

/**
 * Branches domain, extracted from CrmService (SRP): branch CRUD. Leaf domain —
 * touches only `app.branches` and the shared database/audit/policy
 * collaborators, with no internal callers. The branch-scoping helpers
 * (branchIdExpr/extractBranchId) that filter OTHER entities by branch stay in
 * CrmService; they become the shared BranchScope in B4.
 */
@Injectable()
export class BranchesService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
  ) {}

  private toBranchDto(row: BranchRow) {
    return {
      id: row.id,
      name: row.name,
      address: row.address,
      utcOffsetMinutes: Number(row.utc_offset_minutes ?? 180),
      timezone: row.timezone_name ?? "Europe/Moscow",
      scheduleReferenceVersion: Number(row.schedule_reference_version ?? 1),
      lifecycleState: row.lifecycle_state ?? "active",
      version: Number(row.version ?? 1),
      archivedAt: row.archived_at ?? null,
      archiveReason: row.archive_reason ?? null,
      archiveEffectiveDate: row.archive_effective_date ?? null,
      createdAt: row.created_at,
    };
  }

  async listBranches(actor: ActorContext, query: BranchListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const includeArchived = query.includeArchived ?? false;
    if (
      includeArchived &&
      actor.role !== "director" &&
      actor.role !== "system_admin"
    ) {
      throw new ForbiddenException("Архив филиалов доступен только директору.");
    }
    if (includeArchived) {
      await authorizeCurrentCapability(this.database, actor, "config.crm.edit");
    }
    const limit = Math.min(query.limit ?? 100, 100);
    const q = query.q?.trim();
    const result = await this.database.query<BranchRow>(
      `
        select id, name, address, utc_offset_minutes, timezone_name,
          schedule_reference_version, lifecycle_state, version, archived_at,
          archive_reason, archive_effective_date, created_at
        from app.branches
        where ($4::boolean or deleted_at is null)
          and (
            ${managerAdminRolesSql(currentActorRoleSql("$3"))}
            or ${currentActorRoleSql("$3")} = 'teacher'
          )
          and ${managerBranchScopeSql({
            roleExpression: currentActorRoleSql("$3"),
            userIdExpression: "$3",
            branchExpression: "branches.id::text",
          })}
          and (
            $1::text is null
            or lower(coalesce(name, '') || ' ' || coalesce(address, '')) like lower('%' || $1 || '%')
          )
        order by name asc, id asc
        limit $2
      `,
      [q || null, limit, actor.userId, includeArchived],
    );

    return { items: result.rows.map((row) => this.toBranchDto(row)) };
  }

  async createBranch(actor: ActorContext, dto: CreateBranchDto) {
    this.policy.assertCanManageSystemSettings(actor);
    if (actor.role === "manager") {
      throw new ForbiddenException("Создавать филиалы может только директор.");
    }
    const name = dto.name?.trim();
    if (!name) {
      throw new BadRequestException("Название филиала обязательно.");
    }
    this.assertTimezone(dto.timezone);
    if (!dto.weeklyHours?.length) {
      throw new BadRequestException(
        "Укажите рабочие часы хотя бы для одного дня.",
      );
    }
    assertBranchHours(dto.weeklyHours, []);
    // Default to Moscow (UTC+3 / 180 minutes) when no offset is provided.
    const utcOffsetMinutes = dto.utcOffsetMinutes ?? 180;
    const result = await this.database.query<BranchRow>(
      `
        with created as (
          insert into app.branches (
            name, address, utc_offset_minutes, timezone_name
          )
          values ($1, $2, $3, coalesce($4, 'Europe/Moscow'))
          returning id, name, address, utc_offset_minutes, timezone_name,
            schedule_reference_version, lifecycle_state, version, archived_at,
            archive_reason, archive_effective_date, created_at
        ), inserted_hours as (
          insert into app.branch_hours (
            branch_id, weekday, open_local, close_local
          )
          select created.id, hours.weekday, hours.open::time, hours.close::time
          from created
          cross join jsonb_to_recordset($5::jsonb)
            as hours(weekday integer, open text, close text)
          returning branch_id
        ), aggregate_seed as (
          insert into app.aggregate_versions (
            aggregate_type, aggregate_id, version
          )
          select 'organization:branch', id::text, version from created
          on conflict (aggregate_type, aggregate_id) do nothing
        )
        select * from created
      `,
      [
        name,
        dto.address?.trim() || null,
        utcOffsetMinutes,
        dto.timezone?.trim() || null,
        JSON.stringify(dto.weeklyHours),
      ],
    );
    const branch = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.branch_created",
      entityType: "branch",
      entityId: branch.id,
      metadata: {
        utcOffsetMinutes,
        timezone: branch.timezone_name ?? "Europe/Moscow",
        weeklyHoursCount: dto.weeklyHours.length,
      },
    });
    return this.toBranchDto(branch);
  }

  async updateBranch(
    actor: ActorContext,
    branchId: string,
    dto: UpdateBranchDto,
  ) {
    this.policy.assertCanManageSystemSettings(actor);
    await assertSettingsBranchScope(this.database, actor, branchId);
    this.assertTimezone(dto.timezone);
    const result = await this.database.query<BranchRow>(
      `
        update app.branches
        set name = coalesce($2, name),
          address = coalesce($3, address),
          utc_offset_minutes = coalesce($4, utc_offset_minutes),
          timezone_name = coalesce($5, timezone_name),
          updated_at = now()
        where id = $1 and deleted_at is null
        returning id, name, address, utc_offset_minutes, timezone_name,
          schedule_reference_version, lifecycle_state, version, archived_at,
          archive_reason, archive_effective_date, created_at
      `,
      [
        branchId,
        dto.name?.trim() || null,
        dto.address?.trim() ?? null,
        dto.utcOffsetMinutes ?? null,
        dto.timezone?.trim() || null,
      ],
    );
    const branch = result.rows[0];
    if (!branch) throw new NotFoundException("Филиал не найден.");
    await this.audit.record({
      actor,
      action: "crm.branch_updated",
      entityType: "branch",
      entityId: branch.id,
      metadata: {
        utcOffsetMinutes: dto.utcOffsetMinutes,
        timezone: dto.timezone,
      },
    });
    return this.toBranchDto(branch);
  }

  private assertTimezone(timezone?: string) {
    if (!timezone) return;
    try {
      new Intl.DateTimeFormat("en-US", { timeZone: timezone }).format();
    } catch {
      throw new BadRequestException("Неизвестный часовой пояс филиала.");
    }
  }
}
