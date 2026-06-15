import { Body, Controller, Get, Patch, UseGuards } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { Roles } from "../common/security/roles.decorator";
import { RolesGuard } from "../common/security/roles.guard";
import { UpdateAdminChatAvatarDto } from "./dto/update-admin-chat-avatar.dto";
import { UpdateCrmCustomFieldsDto } from "./dto/update-crm-custom-fields.dto";
import { SettingsService } from "./settings.service";

@UseGuards(JwtAuthGuard)
@Controller("settings")
export class SettingsController {
  constructor(private readonly settings: SettingsService) {}

  @Get("admin-chat-avatar")
  getAdminChatAvatar(@CurrentActor() actor: ActorContext) {
    return this.settings.getAdminChatAvatar(actor);
  }

  @Get("crm-custom-fields")
  getCrmCustomFields(@CurrentActor() actor: ActorContext) {
    return this.settings.getCrmCustomFields(actor);
  }
}

@UseGuards(JwtAuthGuard, RolesGuard)
@Controller("admin/settings")
export class AdminSettingsController {
  constructor(private readonly settings: SettingsService) {}

  @Patch("admin-chat-avatar")
  @Roles("admin")
  updateAdminChatAvatar(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpdateAdminChatAvatarDto,
  ) {
    return this.settings.updateAdminChatAvatar(actor, dto.url);
  }

  @Patch("crm-custom-fields")
  @Roles("admin")
  updateCrmCustomFields(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpdateCrmCustomFieldsDto,
  ) {
    return this.settings.updateCrmCustomFields(actor, dto.fields);
  }
}
