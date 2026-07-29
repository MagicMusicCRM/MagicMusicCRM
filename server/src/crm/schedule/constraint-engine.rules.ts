import {
  CONSTRAINT_VIOLATION_CODES,
  ConstraintResourceRef,
  ConstraintViolation,
  ConstraintViolationCode,
  ResolvedConstraintReference,
} from "./constraint-engine.types";

const VIOLATION_ORDER = new Map<ConstraintViolationCode, number>(
  CONSTRAINT_VIOLATION_CODES.map((code, index) => [code, index]),
);

export interface ValidInterval {
  startAt: Date;
  endAt: Date;
}

export function parseConstraintInterval(
  startInput: string | Date,
  endInput: string | Date,
): ValidInterval | null {
  const startAt = new Date(startInput);
  const endAt = new Date(endInput);
  if (
    !Number.isFinite(startAt.getTime()) ||
    !Number.isFinite(endAt.getTime()) ||
    startAt >= endAt
  ) {
    return null;
  }
  return { startAt, endAt };
}

export function halfOpenIntervalsOverlap(
  left: ValidInterval,
  right: ValidInterval,
): boolean {
  return left.startAt < right.endAt && right.startAt < left.endAt;
}

export function intervalCovers(
  container: ValidInterval,
  interval: ValidInterval,
): boolean {
  return (
    container.startAt.getTime() <= interval.startAt.getTime() &&
    container.endAt.getTime() >= interval.endAt.getTime()
  );
}

export function evaluateReferenceConstraints(
  interval: ValidInterval,
  reference: ResolvedConstraintReference | null,
  resource: {
    branchId: string;
    teacherId: string;
  },
): ConstraintViolation[] {
  const branchResource = { type: "branch", id: resource.branchId } as const;
  const teacherResource = {
    type: "teacher",
    id: resource.teacherId,
  } as const;
  if (!reference) {
    return [
      violation("OUTSIDE_BRANCH_HOURS", branchResource),
      violation("TEACHER_UNAVAILABLE", teacherResource),
      violation("TEACHER_BRANCH_MISMATCH", teacherResource),
    ];
  }

  const violations: ConstraintViolation[] = [];
  const branchCovered = reference.branchWindows.some((window) => {
    const parsed = parseConstraintInterval(window.opensAt, window.closesAt);
    return parsed !== null && intervalCovers(parsed, interval);
  });
  if (!branchCovered) {
    violations.push(violation("OUTSIDE_BRANCH_HOURS", branchResource));
  }

  if (!reference.teacherBranchAssigned) {
    violations.push(
      violation("TEACHER_BRANCH_MISMATCH", teacherResource),
    );
  }

  const parsedRules = reference.teacherRules.flatMap((rule) => {
    const endAt = rule.endsAt ?? new Date(8_640_000_000_000_000);
    const parsed = parseConstraintInterval(rule.startsAt, endAt);
    return parsed ? [{ ...rule, interval: parsed }] : [];
  });
  const unavailable = parsedRules.filter(
    (rule) =>
      !rule.available && halfOpenIntervalsOverlap(rule.interval, interval),
  );
  const available = parsedRules.filter((rule) => rule.available);
  const hasPositiveCoverage =
    available.length === 0 ||
    available.some((rule) => intervalCovers(rule.interval, interval));
  if (unavailable.length > 0 || !hasPositiveCoverage) {
    violations.push(
      violation(
        "TEACHER_UNAVAILABLE",
        teacherResource,
        unavailable.length > 0
          ? unavailable.map((rule) => rule.id)
          : available.map((rule) => rule.id),
      ),
    );
  }
  return violations;
}

export function sortConstraintViolations(
  violations: ConstraintViolation[],
): ConstraintViolation[] {
  return violations
    .map((item) => ({
      ...item,
      conflictingLessonIds: [...new Set(item.conflictingLessonIds)].sort(),
      ruleIds: [...new Set(item.ruleIds)].sort(),
    }))
    .sort((left, right) => {
      const codeOrder =
        (VIOLATION_ORDER.get(left.code) ?? Number.MAX_SAFE_INTEGER) -
        (VIOLATION_ORDER.get(right.code) ?? Number.MAX_SAFE_INTEGER);
      if (codeOrder !== 0) return codeOrder;
      const typeOrder = left.resource.type.localeCompare(right.resource.type);
      if (typeOrder !== 0) return typeOrder;
      return left.resource.id.localeCompare(right.resource.id);
    });
}

export function violation(
  code: ConstraintViolationCode,
  resource: ConstraintResourceRef,
  ruleIds: string[] = [],
  conflictingLessonIds: string[] = [],
): ConstraintViolation {
  return {
    code,
    resource,
    conflictingLessonIds,
    ruleIds,
  };
}
