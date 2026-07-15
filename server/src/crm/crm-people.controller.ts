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
import { StaffService } from "./staff.service";
import { TeachersService } from "./teachers.service";
import { PayrollService } from "./payroll.service";
import { CreateStaffDto } from "./dto/create-staff.dto";
import { CreateTeacherDto } from "./dto/create-teacher.dto";
import { StaffListQuery } from "./dto/staff-list.query";
import { TeacherListQuery } from "./dto/teacher-list.query";
import { UpdateStaffDto } from "./dto/update-staff.dto";
import { UpdateTeacherDto } from "./dto/update-teacher.dto";
import { CreateTeacherPayoutDto } from "./dto/create-teacher-payout.dto";
import { SetTeacherRateDto } from "./dto/set-teacher-rate.dto";
import { TeacherStatsQuery } from "./dto/teacher-stats.query";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmPeopleController {
  constructor(
    private readonly payroll: PayrollService,
    private readonly staff: StaffService,
    private readonly teachers: TeachersService,
  ) {}

  @Get("teachers")
  listTeachers(
    @CurrentActor() actor: ActorContext,
    @Query() query: TeacherListQuery,
  ) {
    return this.teachers.listTeachers(actor, query);
  }

  @Post("teachers")
  createTeacher(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateTeacherDto,
  ) {
    return this.teachers.createTeacher(actor, dto);
  }

  @Patch("teachers/:id")
  updateTeacher(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateTeacherDto,
  ) {
    return this.teachers.updateTeacher(actor, id, dto);
  }

  @Get("teachers/:id/payroll")
  getTeacherPayroll(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.payroll.getTeacherPayroll(actor, id);
  }

  @Post("teachers/:id/payouts")
  createTeacherPayout(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CreateTeacherPayoutDto,
  ) {
    return this.payroll.createTeacherPayout(actor, id, dto);
  }

  @Post("teachers/:id/rates")
  setTeacherRate(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: SetTeacherRateDto,
  ) {
    return this.payroll.setTeacherRate(actor, id, dto);
  }

  @Get("reports/teacher-stats")
  getTeacherStats(
    @CurrentActor() actor: ActorContext,
    @Query() query: TeacherStatsQuery,
  ) {
    return this.payroll.getTeacherStatsReport(actor, query);
  }

  @Get("staff")
  listStaff(
    @CurrentActor() actor: ActorContext,
    @Query() query: StaffListQuery,
  ) {
    return this.staff.listStaff(actor, query);
  }

  @Post("staff")
  createStaff(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateStaffDto,
  ) {
    return this.staff.createStaff(actor, dto);
  }

  @Patch("staff/:id")
  updateStaff(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateStaffDto,
  ) {
    return this.staff.updateStaff(actor, id, dto);
  }
}
