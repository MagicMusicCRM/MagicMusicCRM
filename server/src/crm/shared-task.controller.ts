import {
  Body,
  Controller,
  Get,
  Headers,
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
import {
  CloseSharedTaskDto,
  CreateSharedTaskDto,
  PreviewSharedTaskAudienceDto,
  SharedTaskListQuery,
  UpdateSharedTaskDto,
} from "./dto/shared-task.dto";
import { SharedTaskService } from "./tasks/shared-task.service";

@UseGuards(JwtAuthGuard)
@Controller("crm/shared-tasks")
export class SharedTaskController {
  constructor(private readonly tasks: SharedTaskService) {}

  @Get()
  list(
    @CurrentActor() actor: ActorContext,
    @Query() query: SharedTaskListQuery,
  ) {
    return this.tasks.list(actor, query);
  }

  @Get(":taskId/history")
  history(
    @CurrentActor() actor: ActorContext,
    @Param("taskId", ParseUUIDPipe) taskId: string,
  ) {
    return this.tasks.history(actor, taskId);
  }

  @Post("audience-preview")
  audiencePreview(
    @CurrentActor() actor: ActorContext,
    @Body() dto: PreviewSharedTaskAudienceDto,
  ) {
    return this.tasks.previewAudience(actor, dto.audiences);
  }

  @Post()
  create(
    @CurrentActor() actor: ActorContext,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: CreateSharedTaskDto,
  ) {
    return this.tasks.create(actor, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Patch(":taskId")
  update(
    @CurrentActor() actor: ActorContext,
    @Param("taskId", ParseUUIDPipe) taskId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: UpdateSharedTaskDto,
  ) {
    return this.tasks.update(actor, taskId, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post(":taskId/close")
  close(
    @CurrentActor() actor: ActorContext,
    @Param("taskId", ParseUUIDPipe) taskId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: CloseSharedTaskDto,
  ) {
    return this.tasks.close(actor, taskId, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }
}
