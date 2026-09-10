import { Body, Controller, Headers, Param, ParseUUIDPipe, Post, UseGuards } from "@nestjs/common";
import type { ActorContext } from "../../common/security/actor-context";
import { CurrentActor } from "../../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../../common/security/jwt-auth.guard";
import { SchedulePlanArchiveCommandDto } from "../dto/schedule-plan-archive.dto";
import { SchedulePlanArchiveService } from "./schedule-plan-archive.service";

@UseGuards(JwtAuthGuard)
@Controller("crm/schedule-plans")
export class SchedulePlanArchiveController {
  constructor(private readonly archives: SchedulePlanArchiveService) {}
  @Post(":id/restore/preview")
  previewRestore(@CurrentActor() actor: ActorContext, @Param("id", ParseUUIDPipe) id: string) {
    return this.archives.previewRestore(actor, id);
  }

  @Post(":id/restore")
  restore(@CurrentActor() actor: ActorContext, @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: SchedulePlanArchiveCommandDto,
    @Headers("idempotency-key") idempotencyKey?: string, @Headers("x-request-id") requestId?: string) {
    return this.archives.restore(actor, id, dto, { idempotencyKey: idempotencyKey ?? "", requestId: requestId ?? "" });
  }

  @Post(":id/archive/preview")
  preview(@CurrentActor() actor: ActorContext, @Param("id", ParseUUIDPipe) id: string) {
    return this.archives.preview(actor, id);
  }
  @Post(":id/archive")
  archive(@CurrentActor() actor: ActorContext, @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: SchedulePlanArchiveCommandDto,
    @Headers("idempotency-key") idempotencyKey?: string, @Headers("x-request-id") requestId?: string) {
    return this.archives.archive(actor, id, dto, { idempotencyKey: idempotencyKey ?? "", requestId: requestId ?? "" });
  }
}
