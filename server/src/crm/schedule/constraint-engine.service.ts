import { Injectable } from "@nestjs/common";
import {
  evaluateReferenceConstraints,
  parseConstraintInterval,
  sortConstraintViolations,
  violation,
} from "./constraint-engine.rules";
import { ConstraintEngineRepository } from "./constraint-engine.repository";
import {
  ConstraintValidationResult,
  ConstraintViolation,
  LessonConstraintDraft,
  LessonConflict,
  ConstraintTransaction,
} from "./constraint-engine.types";

@Injectable()
export class ScheduleConstraintEngine {
  constructor(private readonly repository: ConstraintEngineRepository) {}

  async validate(
    draft: LessonConstraintDraft,
    transaction?: ConstraintTransaction,
  ): Promise<ConstraintValidationResult> {
    const interval = parseConstraintInterval(draft.startAt, draft.endAt);
    if (!interval) {
      return {
        valid: false,
        violations: [
          violation("INVALID_INTERVAL", {
            type: "interval",
            id: "lesson",
          }),
        ],
      };
    }

    const [reference, roomMatchesBranch, conflicts] = await Promise.all([
      this.repository.resolveReference(
        draft,
        interval.startAt,
        interval.endAt,
        transaction,
      ),
      this.repository.roomMatchesBranch(
        draft.roomId,
        draft.branchId,
        transaction,
      ),
      this.repository.findConflicts(
        draft,
        interval.startAt,
        interval.endAt,
        transaction,
      ),
    ]);
    const violations = [
      ...evaluateReferenceConstraints(interval, reference, {
        branchId: draft.branchId,
        teacherId: draft.teacherId,
      }),
      ...(!roomMatchesBranch
        ? [
            violation("ROOM_BRANCH_MISMATCH", {
              type: "room",
              id: draft.roomId,
            }),
          ]
        : []),
      ...this.groupConflicts(conflicts),
    ];
    const sorted = sortConstraintViolations(violations);
    return { valid: sorted.length === 0, violations: sorted };
  }

  private groupConflicts(conflicts: LessonConflict[]): ConstraintViolation[] {
    const grouped = new Map<string, ConstraintViolation>();
    for (const conflict of conflicts) {
      const key = [
        conflict.code,
        conflict.resource.type,
        conflict.resource.id,
      ].join(":");
      const current = grouped.get(key);
      if (current) {
        current.conflictingLessonIds.push(conflict.lessonId);
      } else {
        grouped.set(
          key,
          violation(
            conflict.code,
            conflict.resource,
            [],
            [conflict.lessonId],
          ),
        );
      }
    }
    return [...grouped.values()];
  }
}
