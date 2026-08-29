import {
  Body,
  Controller,
  Delete,
  Get,
  Header,
  Headers,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  Res,
  UseGuards,
} from "@nestjs/common";
import { Response } from "express";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { Roles } from "../common/security/roles.decorator";
import { RolesGuard } from "../common/security/roles.guard";
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
import {
  DeleteTeacherPayrollEntryDto,
  UpdateTeacherPayoutEntryDto,
  UpdateTeacherRateEntryDto,
} from "./dto/manage-teacher-payroll-entry.dto";
import { TeacherStatsQuery } from "./dto/teacher-stats.query";
import { ProvisionPersonAccessDto } from "./dto/provision-person-access.dto";
import { PersonLifecycleCommandDto } from "./dto/person-lifecycle.dto";
import { PersonLifecycleService } from "./person-lifecycle.service";
import { XLSX_MIME } from "../common/ooxml-workbook.builder";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmPeopleController {
  constructor(
    private readonly payroll: PayrollService,
    private readonly staff: StaffService,
    private readonly teachers: TeachersService,
    private readonly peopleLifecycle: PersonLifecycleService,
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

  @Get("teachers/:id")
  getTeacher(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.teachers.getTeacher(actor, id);
  }

  @Patch("teachers/:id")
  updateTeacher(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: UpdateTeacherDto,
  ) {
    return this.teachers.updateTeacher(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("teachers/:id/access")
  provisionTeacherAccess(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ProvisionPersonAccessDto,
  ) {
    return this.teachers.provisionAccess(actor, id, dto);
  }

  @Get("teachers/:id/access")
  @UseGuards(RolesGuard)
  @Roles("director", "system_admin")
  @Header("Cache-Control", "no-store")
  @Header("Pragma", "no-cache")
  readTeacherAccess(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.teachers.readAccess(actor, id);
  }

  @Get("teachers/:id/lifecycle-preview")
  previewTeacherLifecycle(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.peopleLifecycle.preview(actor, "teacher", id);
  }

  @Get("teachers/:id/lifecycle-history")
  teacherLifecycleHistory(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.peopleLifecycle.history(actor, "teacher", id);
  }

  @Post("teachers/:id/offboard")
  offboardTeacher(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: PersonLifecycleCommandDto,
  ) {
    return this.peopleLifecycle.offboard(actor, "teacher", id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("teachers/:id/restore")
  restoreTeacher(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: PersonLifecycleCommandDto,
  ) {
    return this.peopleLifecycle.restore(actor, "teacher", id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
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
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: CreateTeacherPayoutDto,
  ) {
    return this.payroll.createTeacherPayout(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("teachers/:id/rates")
  setTeacherRate(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: SetTeacherRateDto,
  ) {
    return this.payroll.setTeacherRate(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Patch("teachers/:id/rates/:entryId")
  updateTeacherRate(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("entryId", ParseUUIDPipe) entryId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: UpdateTeacherRateEntryDto,
  ) {
    return this.payroll.updateTeacherRate(actor, id, entryId, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Delete("teachers/:id/rates/:entryId")
  deleteTeacherRate(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("entryId", ParseUUIDPipe) entryId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: DeleteTeacherPayrollEntryDto,
  ) {
    return this.payroll.deleteTeacherRate(actor, id, entryId, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Patch("teachers/:id/payouts/:entryId")
  updateTeacherPayout(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("entryId", ParseUUIDPipe) entryId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: UpdateTeacherPayoutEntryDto,
  ) {
    return this.payroll.updateTeacherPayout(actor, id, entryId, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Delete("teachers/:id/payouts/:entryId")
  deleteTeacherPayout(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("entryId", ParseUUIDPipe) entryId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: DeleteTeacherPayrollEntryDto,
  ) {
    return this.payroll.deleteTeacherPayout(actor, id, entryId, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Get("reports/teacher-stats")
  getTeacherStats(
    @CurrentActor() actor: ActorContext,
    @Query() query: TeacherStatsQuery,
  ) {
    return this.payroll.getTeacherStatsReport(actor, query);
  }

  @Get("reports/teacher-stats/export")
  async exportTeacherStats(
    @CurrentActor() actor: ActorContext,
    @Query() query: TeacherStatsQuery,
    @Res({ passthrough: true }) res: Response,
  ) {
    const xlsx = await this.payroll.exportTeacherStatsReport(actor, query);
    res.set({
      "Content-Type": XLSX_MIME,
      "Content-Disposition": 'attachment; filename="teacher-stats.xlsx"',
    });
    return xlsx;
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

  @Get("staff/:id")
  getStaff(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.staff.getStaff(actor, id);
  }

  @Post("staff/:id/access")
  provisionStaffAccess(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ProvisionPersonAccessDto,
  ) {
    return this.staff.provisionAccess(actor, id, dto);
  }

  @Get("staff/:id/access")
  @UseGuards(RolesGuard)
  @Roles("director", "system_admin")
  @Header("Cache-Control", "no-store")
  @Header("Pragma", "no-cache")
  readStaffAccess(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.staff.readAccess(actor, id);
  }

  @Get("staff/:id/lifecycle-preview")
  previewStaffLifecycle(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.peopleLifecycle.preview(actor, "staff", id);
  }

  @Get("staff/:id/lifecycle-history")
  staffLifecycleHistory(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.peopleLifecycle.history(actor, "staff", id);
  }

  @Post("staff/:id/offboard")
  offboardStaff(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: PersonLifecycleCommandDto,
  ) {
    return this.peopleLifecycle.offboard(actor, "staff", id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("staff/:id/restore")
  restoreStaff(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: PersonLifecycleCommandDto,
  ) {
    return this.peopleLifecycle.restore(actor, "staff", id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }
}
