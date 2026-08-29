import { Injectable } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CreateTeacherPayoutDto } from "./dto/create-teacher-payout.dto";
import {
  DeleteTeacherPayrollEntryDto,
  UpdateTeacherPayoutEntryDto,
  UpdateTeacherRateEntryDto,
} from "./dto/manage-teacher-payroll-entry.dto";
import { SetTeacherRateDto } from "./dto/set-teacher-rate.dto";
import { TeacherStatsQuery } from "./dto/teacher-stats.query";
import { TeacherPayrollCommandService } from "./payroll/teacher-payroll-command.service";
import { TeacherPayrollQueryService } from "./payroll/teacher-payroll-query.service";
import { TeacherStatsXlsxService } from "./payroll/teacher-stats-xlsx.service";
import { TeacherStatsReportService } from "./payroll/teacher-stats-report.service";

export type {
  TeacherRateEntry,
  TeacherStatsUnitType,
} from "./payroll/payroll.types";

@Injectable()
export class PayrollService {
  constructor(
    private readonly query: TeacherPayrollQueryService,
    private readonly commands: TeacherPayrollCommandService,
    private readonly report: TeacherStatsReportService,
    private readonly xlsx: TeacherStatsXlsxService,
  ) {}

  async getTeacherPayroll(actor: ActorContext, teacherId: string) {
    return this.query.getTeacherPayroll(actor, teacherId);
  }

  async createTeacherPayout(
    actor: ActorContext,
    teacherId: string,
    dto: CreateTeacherPayoutDto,
    metadata: { idempotencyKey: string; requestId: string },
  ) {
    return this.commands.createTeacherPayout(actor, teacherId, dto, metadata);
  }

  async setTeacherRate(
    actor: ActorContext,
    teacherId: string,
    dto: SetTeacherRateDto,
    metadata: { idempotencyKey: string; requestId: string },
  ) {
    return this.commands.setTeacherRate(actor, teacherId, dto, metadata);
  }

  async updateTeacherRate(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: UpdateTeacherRateEntryDto,
    metadata: { idempotencyKey: string; requestId: string },
  ) {
    return this.commands.updateTeacherRate(
      actor,
      teacherId,
      entryId,
      dto,
      metadata,
    );
  }

  async deleteTeacherRate(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: DeleteTeacherPayrollEntryDto,
    metadata: { idempotencyKey: string; requestId: string },
  ) {
    return this.commands.deleteTeacherRate(
      actor,
      teacherId,
      entryId,
      dto,
      metadata,
    );
  }

  async updateTeacherPayout(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: UpdateTeacherPayoutEntryDto,
    metadata: { idempotencyKey: string; requestId: string },
  ) {
    return this.commands.updateTeacherPayout(
      actor,
      teacherId,
      entryId,
      dto,
      metadata,
    );
  }

  async deleteTeacherPayout(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: DeleteTeacherPayrollEntryDto,
    metadata: { idempotencyKey: string; requestId: string },
  ) {
    return this.commands.deleteTeacherPayout(
      actor,
      teacherId,
      entryId,
      dto,
      metadata,
    );
  }

  async getTeacherStatsReport(actor: ActorContext, query: TeacherStatsQuery) {
    return this.report.getTeacherStatsReport(actor, query);
  }

  async exportTeacherStatsReport(
    actor: ActorContext,
    query: TeacherStatsQuery,
  ): Promise<Buffer> {
    return this.xlsx.exportTeacherStatsReport(actor, query);
  }
}
