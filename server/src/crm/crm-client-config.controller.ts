import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { ClientConfigService } from "./clients/client-config.service";
import {
  ClientConfigListQuery,
  CreateClientCustomFieldDto,
  CreateLeadSourceDto,
  ExpectedVersionQuery,
  UpdateClientCustomFieldDto,
  UpdateLeadSourceDto,
} from "./dto/client-config.dto";

@UseGuards(JwtAuthGuard)
@Controller("crm/client-config")
export class CrmClientConfigController {
  constructor(private readonly config: ClientConfigService) {}

  @Get("sources")
  listSources(
    @CurrentActor() actor: ActorContext,
    @Query() query: ClientConfigListQuery,
  ) {
    return this.config.listSources(actor, query);
  }

  @Post("sources")
  createSource(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateLeadSourceDto,
  ) {
    return this.config.createSource(actor, dto);
  }

  @Patch("sources/:id")
  updateSource(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateLeadSourceDto,
  ) {
    return this.config.updateSource(actor, id, dto);
  }

  @Delete("sources/:id")
  archiveSource(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Query() query: ExpectedVersionQuery,
  ) {
    return this.config.updateSource(actor, id, {
      expectedVersion: query.expectedVersion,
      isActive: false,
    });
  }

  @Get("fields")
  listFields(
    @CurrentActor() actor: ActorContext,
    @Query() query: ClientConfigListQuery,
  ) {
    return this.config.listFields(actor, query);
  }

  @Post("fields")
  createField(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateClientCustomFieldDto,
  ) {
    return this.config.createField(actor, dto);
  }

  @Patch("fields/:id")
  updateField(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateClientCustomFieldDto,
  ) {
    return this.config.updateField(actor, id, dto);
  }

  @Delete("fields/:id")
  archiveField(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Query() query: ExpectedVersionQuery,
  ) {
    return this.config.updateField(actor, id, {
      expectedVersion: query.expectedVersion,
      isActive: false,
    });
  }
}
