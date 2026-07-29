import { BadRequestException } from "@nestjs/common";
import {
  BranchHoursExceptionDto,
  BranchWeeklyHoursDto,
  TeacherAvailabilityRuleDto,
  TeacherBranchAssignmentDto,
} from "./availability.dto";

const MAX_REFERENCE_RANGE_MS = 32 * 24 * 60 * 60 * 1000;

export function parseReferenceRange(fromInput: string, toInput: string) {
  const from = new Date(fromInput);
  const to = new Date(toInput);
  if (
    !Number.isFinite(from.getTime()) ||
    !Number.isFinite(to.getTime()) ||
    from >= to
  ) {
    throw new BadRequestException("Reference interval must satisfy from < to.");
  }
  if (to.getTime() - from.getTime() > MAX_REFERENCE_RANGE_MS) {
    throw new BadRequestException("Reference interval cannot exceed 32 days.");
  }
  return { from, to };
}

export function assertBranchHours(
  weekly: BranchWeeklyHoursDto[],
  exceptions: BranchHoursExceptionDto[],
) {
  if (new Set(weekly.map((row) => row.weekday)).size !== weekly.length) {
    throw new BadRequestException("Weekday must be unique per branch.");
  }
  if (new Set(exceptions.map((row) => row.date)).size !== exceptions.length) {
    throw new BadRequestException("Exception date must be unique per branch.");
  }
  for (const row of weekly) {
    if (row.open >= row.close) {
      throw new BadRequestException("Branch opening time must precede closing.");
    }
  }
  for (const row of exceptions) {
    const hasTimes = row.open !== undefined || row.close !== undefined;
    if (
      (row.closed && hasTimes) ||
      (!row.closed &&
        (!row.open || !row.close || row.open >= row.close))
    ) {
      throw new BadRequestException("Invalid branch-hours exception.");
    }
  }
}

export function assertTeacherBranches(
  assignments: TeacherBranchAssignmentDto[],
) {
  if (
    new Set(assignments.map((row) => row.branchId)).size !== assignments.length
  ) {
    throw new BadRequestException("Teacher branch must be unique.");
  }
  for (const row of assignments) {
    if (
      row.activeFrom &&
      row.activeUntil &&
      row.activeUntil < row.activeFrom
    ) {
      throw new BadRequestException("Teacher branch interval is invalid.");
    }
  }
}

export function assertAvailabilityRules(rules: TeacherAvailabilityRuleDto[]) {
  for (const rule of rules) {
    if (rule.kind === "recurring") {
      if (
        rule.weekday === undefined ||
        !rule.localStart ||
        !rule.localEnd ||
        !rule.validFrom ||
        rule.localStart >= rule.localEnd ||
        (rule.validUntil !== undefined && rule.validUntil < rule.validFrom) ||
        rule.startsAt !== undefined ||
        rule.endsAt !== undefined
      ) {
        throw new BadRequestException("Invalid recurring availability rule.");
      }
      continue;
    }
    const startsAt = rule.startsAt ? new Date(rule.startsAt) : null;
    const endsAt = rule.endsAt ? new Date(rule.endsAt) : null;
    if (
      rule.weekday !== undefined ||
      rule.localStart !== undefined ||
      rule.localEnd !== undefined ||
      rule.validFrom !== undefined ||
      rule.validUntil !== undefined ||
      !startsAt ||
      !Number.isFinite(startsAt.getTime()) ||
      (endsAt !== null && endsAt <= startsAt) ||
      (rule.available && endsAt === null)
    ) {
      throw new BadRequestException("Invalid interval availability rule.");
    }
  }
}
