import { UnprocessableEntityException } from "@nestjs/common";
import { UpsertLessonDto } from "../dto/upsert-lesson.dto";
import { assertLessonPatchUsesTransition } from "./lesson-protected-patch.guard";

describe("lesson protected PATCH boundary", () => {
  it.each([
    "scheduledAt",
    "durationMinutes",
    "teacherId",
    "branchId",
    "roomId",
    "studentId",
    "leadId",
    "groupId",
    "isTrial",
    "teacherRate",
  ] as const)("rejects direct %s writes", (field) => {
    expect(() => assertLessonPatchUsesTransition({
      expectedVersion: 1,
      notes: "allowed",
      [field]: "attempted",
    } as unknown as UpsertLessonDto)).toThrow(UnprocessableEntityException);
  });

  it("allows one notes-only patch and rejects an empty patch", () => {
    expect(() => assertLessonPatchUsesTransition({
      expectedVersion: 1,
      notes: "Комментарий",
    })).not.toThrow();
    expect(() => assertLessonPatchUsesTransition({
      expectedVersion: 1,
    })).toThrow(UnprocessableEntityException);
  });
});
