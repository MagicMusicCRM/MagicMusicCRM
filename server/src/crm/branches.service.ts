import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CreateBranchDto } from "./dto/create-branch.dto";
import { CrmListQuery } from "./dto/crm-list.query";
import { UpdateBranchDto } from "./dto/update-branch.dto";
import { CrmPolicy } from "./crm.policy";

interface BranchRow {
  id: string;
  name: string;
  address: string | null;
  utc_offset_minutes: number | string;
  timezone_name?: string;
  schedule_reference_version?: number | string;
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
      createdAt: row.created_at,
    };
  }

  async listBranches(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 100, 100);
    const q = query.q?.trim();
    const result = await this.database.query<BranchRow>(
      `
        select id, name, address, utc_offset_minutes, timezone_name,
          schedule_reference_version, created_at
        from app.branches
        where deleted_at is null
          and (
            $1::text is null
            or lower(coalesce(name, '') || ' ' || coalesce(address, '')) like lower('%' || $1 || '%')
          )
        order by name asc, id asc
        limit $2
      `,
      [q || null, limit],
    );

    return { items: result.rows.map((row) => this.toBranchDto(row)) };
  }

  async createBranch(actor: ActorContext, dto: CreateBranchDto) {
    this.policy.assertCanWriteCrm(actor);
    const name = dto.name?.trim();
    if (!name) {
      throw new BadRequestException("Название филиала обязательно.");
    }
    this.assertTimezone(dto.timezone);
    // Default to Moscow (UTC+3 / 180 minutes) when no offset is provided.
    const utcOffsetMinutes = dto.utcOffsetMinutes ?? 180;
    const result = await this.database.query<BranchRow>(
      `
        insert into app.branches (
          name, address, utc_offset_minutes, timezone_name
        )
        values ($1, $2, $3, coalesce($4, 'Europe/Moscow'))
        returning id, name, address, utc_offset_minutes, timezone_name,
          schedule_reference_version, created_at
      `,
      [
        name,
        dto.address?.trim() || null,
        utcOffsetMinutes,
        dto.timezone?.trim() || null,
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
      },
    });
    return this.toBranchDto(branch);
  }

  async updateBranch(
    actor: ActorContext,
    branchId: string,
    dto: UpdateBranchDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
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
          schedule_reference_version, created_at
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
