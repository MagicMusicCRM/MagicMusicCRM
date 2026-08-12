import {
  Body,
  Controller,
  Delete,
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
import { CrmService } from "./crm.service";
import { RoomsService } from "./rooms.service";
import { RoomLifecycleService } from "./room-lifecycle.service";
import { BranchesService } from "./branches.service";
import { BranchLifecycleService } from "./branch-lifecycle.service";
import { GroupsService } from "./groups.service";
import { GroupLifecycleService } from "./group-lifecycle.service";
import { CrmListQuery } from "./dto/crm-list.query";
import {
  BranchLifecycleCommandDto,
  BranchListQuery,
} from "./dto/branch-lifecycle.dto";
import { GroupStudentDto } from "./dto/group-student.dto";
import {
  GroupLifecycleCommandDto,
  GroupListQuery,
} from "./dto/group-lifecycle.dto";
import { RoomAvailabilityQuery } from "./dto/room-availability.query";
import {
  RoomLifecycleCommandDto,
  RoomListQuery,
} from "./dto/room-lifecycle.dto";
import { CreateBranchDto } from "./dto/create-branch.dto";
import { UpdateBranchDto } from "./dto/update-branch.dto";
import { UpsertGroupDto } from "./dto/upsert-group.dto";
import { UpdateGroupDto } from "./dto/update-group.dto";
import { UpsertRoomDto } from "./dto/upsert-room.dto";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmFacilitiesController {
  constructor(
    private readonly branches: BranchesService,
    private readonly branchLifecycle: BranchLifecycleService,
    private readonly crm: CrmService,
    private readonly groups: GroupsService,
    private readonly groupLifecycle: GroupLifecycleService,
    private readonly rooms: RoomsService,
    private readonly roomLifecycle: RoomLifecycleService,
  ) {}

  @Get("branches")
  listBranches(
    @CurrentActor() actor: ActorContext,
    @Query() query: BranchListQuery,
  ) {
    return this.branches.listBranches(actor, query);
  }

  @Post("branches/:id/close-preview")
  previewBranchClose(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.branchLifecycle.preview(actor, id);
  }

  @Post("branches/:id/close")
  closeBranch(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: BranchLifecycleCommandDto,
  ) {
    return this.branchLifecycle.archive(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("branches/:id/restore")
  restoreBranch(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: BranchLifecycleCommandDto,
  ) {
    return this.branchLifecycle.restore(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Get("branches/:id/history")
  branchHistory(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.branchLifecycle.history(actor, id);
  }

  @Post("branches")
  createBranch(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateBranchDto,
  ) {
    return this.branches.createBranch(actor, dto);
  }

  @Patch("branches/:id")
  updateBranch(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateBranchDto,
  ) {
    return this.branches.updateBranch(actor, id, dto);
  }

  @Get("rooms")
  listRooms(
    @CurrentActor() actor: ActorContext,
    @Query() query: RoomListQuery,
  ) {
    return this.rooms.listRooms(actor, query);
  }

  @Get("rooms/availability")
  listRoomAvailability(
    @CurrentActor() actor: ActorContext,
    @Query() query: RoomAvailabilityQuery,
  ) {
    return this.rooms.listRoomAvailability(actor, query);
  }

  @Post("rooms")
  createRoom(@CurrentActor() actor: ActorContext, @Body() dto: UpsertRoomDto) {
    return this.rooms.createRoom(actor, dto);
  }

  @Post("rooms/:id/archive-preview")
  previewRoomArchive(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.roomLifecycle.preview(actor, id);
  }

  @Post("rooms/:id/archive")
  archiveRoom(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: RoomLifecycleCommandDto,
  ) {
    return this.roomLifecycle.archive(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("rooms/:id/restore")
  restoreRoom(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: RoomLifecycleCommandDto,
  ) {
    return this.roomLifecycle.restore(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Get("rooms/:id/history")
  roomHistory(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.roomLifecycle.history(actor, id);
  }

  @Patch("rooms/:id")
  updateRoom(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpsertRoomDto,
  ) {
    return this.rooms.updateRoom(actor, id, dto);
  }

  @Delete("rooms/:id")
  deleteRoom(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.rooms.deleteRoom(actor, id);
  }

  @Get("groups")
  listGroups(
    @CurrentActor() actor: ActorContext,
    @Query() query: GroupListQuery,
  ) {
    return this.groups.listGroups(actor, query);
  }

  @Post("groups/:id/archive-preview")
  previewGroupArchive(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.groupLifecycle.preview(actor, id);
  }

  @Post("groups/:id/archive")
  archiveGroup(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: GroupLifecycleCommandDto,
  ) {
    return this.groupLifecycle.archive(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("groups/:id/restore")
  restoreGroup(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: GroupLifecycleCommandDto,
  ) {
    return this.groupLifecycle.restore(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Get("groups/:id/history")
  groupHistory(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.groupLifecycle.history(actor, id);
  }

  @Post("groups")
  createGroup(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertGroupDto,
  ) {
    return this.groups.createGroup(actor, dto);
  }

  @Get("groups/:id")
  getGroup(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.groups.getGroup(actor, id);
  }

  @Patch("groups/:id")
  updateGroup(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateGroupDto,
  ) {
    return this.groups.updateGroup(actor, id, dto);
  }

  @Get("groups/:id/students")
  listGroupStudents(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Query() query: CrmListQuery,
  ) {
    return this.crm.listGroupStudents(actor, id, query);
  }

  @Post("groups/:id/students")
  addGroupStudent(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: GroupStudentDto,
  ) {
    return this.groups.addGroupStudent(actor, id, dto.studentId);
  }

  @Delete("groups/:id/students/:studentId")
  removeGroupStudent(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("studentId", ParseUUIDPipe) studentId: string,
  ) {
    return this.groups.removeGroupStudent(actor, id, studentId);
  }
}
