import type { SchedulePlanRowDto } from "../dto/schedule-plan.dto";
import type {
  ConstraintResourceType,
  ConstraintViolationCode,
} from "./constraint-engine.types";
import type { LessonSeriesCommandService } from "./lesson-series-command.service";

export type SchedulePlanRowPreview = Awaited<
  ReturnType<LessonSeriesCommandService["previewPlanRow"]>
> & { index: number };

interface SharedResource {
  code: ConstraintViolationCode;
  type: ConstraintResourceType;
  id: string;
}

export class SchedulePlanOverlapAnalyzer {
  addCrossRowViolations(
    rows: SchedulePlanRowDto[],
    previews: SchedulePlanRowPreview[],
    studentIds: string[],
  ): void {
    for (let leftIndex = 0; leftIndex < rows.length; leftIndex += 1) {
      for (
        let rightIndex = leftIndex + 1;
        rightIndex < rows.length;
        rightIndex += 1
      ) {
        this.addPairViolations(
          rows,
          previews,
          studentIds,
          leftIndex,
          rightIndex,
        );
      }
    }
  }

  private addPairViolations(
    rows: SchedulePlanRowDto[],
    previews: SchedulePlanRowPreview[],
    studentIds: string[],
    leftIndex: number,
    rightIndex: number,
  ) {
    const overlap = this.firstOverlap(
      previews[leftIndex]!,
      previews[rightIndex]!,
    );
    if (!overlap) return;
    const shared = this.sharedResources(rows[leftIndex]!, rows[rightIndex]!);
    this.appendSymmetricFailures(
      previews,
      studentIds,
      shared,
      leftIndex,
      rightIndex,
      overlap.left,
      overlap.right,
    );
  }

  private firstOverlap(
    left: SchedulePlanRowPreview,
    right: SchedulePlanRowPreview,
  ) {
    for (const leftOccurrence of left.occurrences) {
      const rightOccurrence = right.occurrences.find(
        (candidate) =>
          Date.parse(leftOccurrence.startAt) < Date.parse(candidate.endAt) &&
          Date.parse(candidate.startAt) < Date.parse(leftOccurrence.endAt),
      );
      if (rightOccurrence)
        return { left: leftOccurrence, right: rightOccurrence };
    }
    return null;
  }

  private sharedResources(
    left: SchedulePlanRowDto,
    right: SchedulePlanRowDto,
  ): SharedResource[] {
    const shared: SharedResource[] = [];
    if (left.teacherId === right.teacherId) {
      shared.push({
        code: "TEACHER_OVERLAP",
        type: "teacher",
        id: left.teacherId,
      });
    }
    if (left.roomId === right.roomId) {
      shared.push({ code: "ROOM_OVERLAP", type: "room", id: left.roomId });
    }
    return shared;
  }

  private appendSymmetricFailures(
    previews: SchedulePlanRowPreview[],
    studentIds: string[],
    shared: SharedResource[],
    leftIndex: number,
    rightIndex: number,
    leftOccurrence: SchedulePlanRowPreview["occurrences"][number],
    rightOccurrence: SchedulePlanRowPreview["occurrences"][number],
  ) {
    this.appendFailures(
      previews[leftIndex]!,
      studentIds,
      shared,
      rightIndex,
      leftOccurrence,
    );
    this.appendFailures(
      previews[rightIndex]!,
      studentIds,
      shared,
      leftIndex,
      rightOccurrence,
    );
  }

  private appendFailures(
    preview: SchedulePlanRowPreview,
    studentIds: string[],
    shared: SharedResource[],
    conflictingRowIndex: number,
    occurrence: SchedulePlanRowPreview["occurrences"][number],
  ) {
    for (const studentId of studentIds) {
      const resources: SharedResource[] = [
        ...shared,
        { code: "CLIENT_OVERLAP", type: "client", id: studentId },
      ];
      preview.failures.push({
        occurrence,
        studentId,
        violations: resources.map((resource) => ({
          code: resource.code,
          resource: { type: resource.type, id: resource.id },
          conflictingLessonIds: [],
          conflictingRowIndexes: [conflictingRowIndex],
          ruleIds: ["schedule_plan.rows"],
        })),
      });
    }
  }
}
