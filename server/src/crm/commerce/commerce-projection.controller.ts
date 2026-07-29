import {
  Controller,
  Get,
  Header,
  Param,
  ParseUUIDPipe,
  UseGuards,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { CurrentActor } from "../../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../../common/security/jwt-auth.guard";
import { CommerceProjectionService } from "./commerce-projection.service";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CommerceProjectionController {
  constructor(private readonly service: CommerceProjectionService) {}

  @Get("me/commerce")
  @Header("Cache-Control", "private, no-store")
  @Header("Vary", "Authorization")
  readSelf(@CurrentActor() actor: ActorContext) {
    return this.service.readSelf(actor);
  }

  @Get("students/:studentId/commerce")
  @Header("Cache-Control", "private, no-store")
  @Header("Vary", "Authorization")
  readStudent(
    @CurrentActor() actor: ActorContext,
    @Param("studentId", ParseUUIDPipe) studentId: string,
  ) {
    return this.service.readStudent(actor, studentId);
  }
}
