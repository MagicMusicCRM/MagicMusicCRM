import { UnprocessableEntityException } from "@nestjs/common";
import { UpsertLessonDto } from "../dto/upsert-lesson.dto";

const PATCH_SAFE_FIELDS = new Set<keyof UpsertLessonDto>([
  "expectedVersion",
  "notes",
]);

export function assertLessonPatchUsesTransition(dto: UpsertLessonDto) {
  const supplied = Object.keys(dto) as Array<keyof UpsertLessonDto>;
  // Transformed DTOs own unassigned class fields; only defined values are writes.
  const protectedFields = supplied.filter(
    (field) => dto[field] !== undefined && !PATCH_SAFE_FIELDS.has(field),
  );
  if (protectedFields.length > 0) {
    throw new UnprocessableEntityException({
      code: "LESSON_TRANSITION_REQUIRED",
      message: "Protected lesson changes require the transition endpoint.",
      fields: protectedFields,
    });
  }
  if (dto.notes === undefined) {
    throw new UnprocessableEntityException({
      code: "LESSON_PATCH_EMPTY",
      message: "A direct lesson patch may update notes only.",
      fields: ["notes"],
    });
  }
}
