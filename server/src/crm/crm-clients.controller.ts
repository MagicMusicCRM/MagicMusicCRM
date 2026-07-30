import {
  BadRequestException,
  Body,
  Controller,
  Param,
  ParseUUIDPipe,
  Post,
  Get,
  Query,
  UseGuards,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { ClientReferenceService } from "./clients/client-reference.service";
import { ClientConversionService } from "./clients/client-conversion.service";
import { ClientArchiveService } from "./clients/client-archive.service";
import { ClientCardReadService } from "./clients/client-card-read.service";
import {
  ArchiveClientCommandDto,
  ArchiveClientPreviewDto,
  ArchiveConvertedLeadDto,
} from "./dto/client-archive.dto";
import { ConvertLeadDto } from "./dto/client-conversion.dto";
import {
  CLIENT_REF_TYPES,
  ClientRefDto,
  ClientRefSearchQuery,
  ClientRefType,
} from "./dto/client-ref.dto";

@UseGuards(JwtAuthGuard)
@Controller("crm/clients")
export class CrmClientsController {
  constructor(
    private readonly clientReferences: ClientReferenceService,
    private readonly conversions: ClientConversionService,
    private readonly archives: ClientArchiveService,
    private readonly clientCards: ClientCardReadService,
  ) {}

  @Get("resolve")
  resolve(
    @CurrentActor() actor: ActorContext,
    @Query() ref: ClientRefDto,
  ) {
    return this.clientReferences.resolve(actor, ref);
  }

  @Get("search")
  search(
    @CurrentActor() actor: ActorContext,
    @Query() query: ClientRefSearchQuery,
  ) {
    return this.clientReferences.search(actor, query);
  }

  @Get(":type/:id/card")
  getCard(
    @CurrentActor() actor: ActorContext,
    @Param("type") type: string,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    if (!(CLIENT_REF_TYPES as readonly string[]).includes(type)) {
      throw new BadRequestException("Неизвестный тип клиента.");
    }
    return this.clientCards.load(actor, { type: type as ClientRefType, id });
  }

  @Post("leads/:leadId/convert")
  convertLead(
    @CurrentActor() actor: ActorContext,
    @Param("leadId", ParseUUIDPipe) leadId: string,
    @Body() dto: ConvertLeadDto,
  ) {
    return this.conversions.convert(actor, leadId, dto);
  }

  @Post("leads/:leadId/archive-source")
  archiveConvertedLead(
    @CurrentActor() actor: ActorContext,
    @Param("leadId", ParseUUIDPipe) leadId: string,
    @Body() dto: ArchiveConvertedLeadDto,
  ) {
    return this.archives.archiveConvertedLead(actor, leadId, dto);
  }

  @Post("archive/preview")
  archivePreview(
    @CurrentActor() actor: ActorContext,
    @Body() dto: ArchiveClientPreviewDto,
  ) {
    return this.archives.preview(actor, dto);
  }

  @Post("archive")
  archiveClient(
    @CurrentActor() actor: ActorContext,
    @Body() dto: ArchiveClientCommandDto,
  ) {
    return this.archives.archive(actor, dto);
  }
}
