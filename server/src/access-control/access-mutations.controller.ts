import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Headers,
  Param,
  ParseUUIDPipe,
  Put,
  UseGuards,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { Roles } from "../common/security/roles.decorator";
import { RolesGuard } from "../common/security/roles.guard";
import {
  AssignAccessRoleDto,
  ReplaceRolePackageDto,
  SetUserOverrideDto,
} from "./dto/access-mutation.dto";
import { AccessMutationsService } from "./access-mutations.service";
import { AccessRole, USER_ROLES } from "./capability-registry";

function parseRole(value: string): AccessRole {
  if (!(USER_ROLES as readonly string[]).includes(value)) {
    throw new BadRequestException({
      code: "INVALID_ACCESS_ROLE",
      message: "Unknown access role.",
    });
  }
  return value as AccessRole;
}

function commandHeaders(
  idempotencyKey: string | undefined,
  requestId: string | undefined,
) {
  return {
    idempotencyKey: idempotencyKey ?? "",
    requestId: requestId ?? "",
  };
}

@UseGuards(JwtAuthGuard, RolesGuard)
@Controller("access")
export class AccessMutationsController {
  constructor(private readonly access: AccessMutationsService) {}

  @Get("me")
  getMyAccess(@CurrentActor() actor: ActorContext) {
    return this.access.getMyAccessSnapshot(actor);
  }

  @Get("role-packages")
  @Roles("director", "system_admin")
  listRolePackages(@CurrentActor() actor: ActorContext) {
    return this.access.listRolePackages(actor);
  }

  @Get("role-packages/:role")
  @Roles("director", "system_admin")
  getRolePackage(
    @CurrentActor() actor: ActorContext,
    @Param("role") role: string,
  ) {
    return this.access.getRolePackage(actor, parseRole(role));
  }

  @Put("role-packages/:role")
  @Roles("director", "system_admin")
  replaceRolePackage(
    @CurrentActor() actor: ActorContext,
    @Param("role") role: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: ReplaceRolePackageDto,
  ) {
    return this.access.replaceRolePackage(actor, {
      role: parseRole(role),
      ...dto,
      ...commandHeaders(idempotencyKey, requestId),
    });
  }

  @Get("users/:userId")
  @Roles("director", "system_admin")
  getUserAccess(
    @CurrentActor() actor: ActorContext,
    @Param("userId", ParseUUIDPipe) userId: string,
  ) {
    return this.access.getUserAccess(actor, userId);
  }

  @Put("users/:userId/role")
  @Roles("director", "system_admin")
  assignRole(
    @CurrentActor() actor: ActorContext,
    @Param("userId", ParseUUIDPipe) userId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: AssignAccessRoleDto,
  ) {
    return this.access.assignRole(actor, {
      userId,
      ...dto,
      ...commandHeaders(idempotencyKey, requestId),
    });
  }

  @Put("users/:userId/overrides/:capabilityKey")
  @Roles("director", "system_admin")
  setUserOverride(
    @CurrentActor() actor: ActorContext,
    @Param("userId", ParseUUIDPipe) userId: string,
    @Param("capabilityKey") capabilityKey: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: SetUserOverrideDto,
  ) {
    return this.access.setUserOverride(actor, {
      userId,
      capabilityKey,
      ...dto,
      ...commandHeaders(idempotencyKey, requestId),
    });
  }
}
