import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../../audit/audit.service";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { CrmPolicy } from "../crm.policy";
import {
  ReplaceBranchHoursDto,
  ReplaceTeacherAvailabilityDto,
  ReplaceTeacherBranchesDto,
  ScheduleReferenceQuery,
} from "./availability.dto";
import { AvailabilityRepository } from "./availability.repository";
import {
  assertAvailabilityRules,
  assertBranchHours,
  assertTeacherBranches,
  parseReferenceRange,
} from "./availability.rules";

@Injectable()
export class AvailabilityService {
  constructor(
    private readonly database: DatabaseService,
    private readonly repository: AvailabilityRepository,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
  ) {}

  async resolve(actor: ActorContext, query: ScheduleReferenceQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const { from, to } = parseReferenceRange(query.from, query.to);
    await this.assertTeacherScope(actor, query.teacherId);
    const reference = await this.repository.resolve(
      query.branchId,
      query.teacherId,
      from,
      to,
    );
    if (!reference) {
      throw new NotFoundException("Schedule reference not found.");
    }
    return reference;
  }

  async replaceBranchHours(
    actor: ActorContext,
    branchId: string,
    dto: ReplaceBranchHoursDto,
  ) {
    this.policy.assertManagerOnly(actor);
    assertBranchHours(dto.weekly, dto.exceptions);
    const result = await this.withScheduleValidation(() =>
      this.database.transaction((client) =>
        this.repository.replaceBranchHours(client, {
          branchId,
          expectedVersion: dto.expectedVersion,
          timezone: dto.timezone,
          weekly: dto.weekly,
          exceptions: dto.exceptions,
        }),
      ),
    );
    if (!result) {
      throw new ConflictException("Branch reference version conflict.");
    }
    await this.audit.record({
      actor,
      action: "crm.branch_hours_replaced",
      entityType: "branch",
      entityId: branchId,
      metadata: {
        version: result.version,
        weeklyCount: dto.weekly.length,
        exceptionCount: dto.exceptions.length,
      },
    });
    return result;
  }

  async replaceTeacherBranches(
    actor: ActorContext,
    teacherId: string,
    dto: ReplaceTeacherBranchesDto,
  ) {
    this.policy.assertManagerOnly(actor);
    assertTeacherBranches(dto.assignments);
    const result = await this.withScheduleValidation(() =>
      this.database.transaction((client) =>
        this.repository.replaceTeacherBranches(client, {
          teacherId,
          expectedVersion: dto.expectedVersion,
          assignments: dto.assignments,
        }),
      ),
    );
    if (!result) {
      throw new ConflictException("Teacher reference version conflict.");
    }
    await this.audit.record({
      actor,
      action: "crm.teacher_branches_replaced",
      entityType: "teacher",
      entityId: teacherId,
      metadata: {
        version: result.version,
        assignmentCount: dto.assignments.length,
      },
    });
    return result;
  }

  async replaceTeacherAvailability(
    actor: ActorContext,
    teacherId: string,
    dto: ReplaceTeacherAvailabilityDto,
  ) {
    this.policy.assertManagerOnly(actor);
    assertAvailabilityRules(dto.rules);
    const result = await this.withScheduleValidation(() =>
      this.database.transaction((client) =>
        this.repository.replaceTeacherAvailability(client, {
          teacherId,
          expectedVersion: dto.expectedVersion,
          rules: dto.rules,
        }),
      ),
    );
    if (!result) {
      throw new ConflictException("Teacher reference version conflict.");
    }
    await this.audit.record({
      actor,
      action: "crm.teacher_availability_replaced",
      entityType: "teacher",
      entityId: teacherId,
      metadata: {
        version: result.version,
        ruleCount: dto.rules.length,
      },
    });
    return result;
  }

  private async assertTeacherScope(actor: ActorContext, teacherId: string) {
    if (actor.role !== "teacher") return;
    const teacher = await this.repository.getTeacherOwner(teacherId);
    if (teacher.rows[0]?.owner_user_id !== actor.userId) {
      throw new NotFoundException("Schedule reference not found.");
    }
  }

  private async withScheduleValidation<T>(work: () => Promise<T>): Promise<T> {
    try {
      return await work();
    } catch (error) {
      if ((error as { code?: string }).code === "23514") {
        throw new BadRequestException(
          (error as { message?: string }).message ?? "Invalid schedule data.",
        );
      }
      throw error;
    }
  }
}
