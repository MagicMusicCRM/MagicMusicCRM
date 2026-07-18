import { Controller, Get, Query, UseGuards } from "@nestjs/common";
import { IsOptional, IsString, MaxLength } from "class-validator";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { listEligibleResponsibles } from "./responsible-eligibility";

export class AdminStaffQuery {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  search?: string;

  // CSV of roles, e.g. "admin,manager,director". Validated against the same
  // strict allowlist as every authoritative responsible write.
  @IsOptional()
  @IsString()
  @MaxLength(200)
  roles?: string;
}

/**
 * Contract 4 (правки №2): GET /api/admin/staff — the responsible picker.
 * Returns [{id, displayName, role}] where id is app.users.id (the same id
 * space custom_data.responsibleUserId uses). Admin+ only.
 */
@UseGuards(JwtAuthGuard)
@Controller("admin")
export class AdminStaffController {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
  ) {}

  @Get("staff")
  listStaff(
    @CurrentActor() actor: ActorContext,
    @Query() query: AdminStaffQuery,
  ) {
    // Preserve the existing route authorization while using one strict source
    // of truth for both picker rows and assignment writes.
    this.policy.assertManagerOnly(actor);
    return listEligibleResponsibles(this.database, query);
  }
}
