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
import { CrmService } from "./crm.service";
import { RoomsService } from "./rooms.service";
import { BranchesService } from "./branches.service";
import { GroupsService } from "./groups.service";
import { CrmListQuery } from "./dto/crm-list.query";
import { GroupStudentDto } from "./dto/group-student.dto";
import { RoomAvailabilityQuery } from "./dto/room-availability.query";
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
    private readonly crm: CrmService,
    private readonly groups: GroupsService,
    private readonly rooms: RoomsService,
  ) {}

  @Get("branches")
  listBranches(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.branches.listBranches(actor, query);
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
  listRooms(@CurrentActor() actor: ActorContext, @Query() query: CrmListQuery) {
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
    @Query() query: CrmListQuery,
  ) {
    return this.groups.listGroups(actor, query);
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
