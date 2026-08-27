import { UnprocessableEntityException } from "@nestjs/common";
import {
  ExistingLessonDraft,
  LessonRequiredFieldValidator,
} from "./lesson-required-field.validator";

describe("LessonRequiredFieldValidator", () => {
  const validator = new LessonRequiredFieldValidator();

  const existingLesson = (
    snapshotState: "valid" | "legacy_incomplete" = "valid",
  ): ExistingLessonDraft => ({
    id: "lesson-a",
    version: 3,
    studentId: "legacy-student-a",
    leadId: null,
    teacherId: "teacher-a",
    branchId: "branch-a",
    roomId: "room-a",
    scheduledAt: new Date("2026-08-27T09:00:00.000Z"),
    durationMinutes: 60,
    isTrial: false,
    notes: " existing note ",
    snapshot: {
      clientType: "student",
      clientId: "student-a",
      completionType: "standard.success",
      clientChargeType: "none",
      clientChargeValue: 0,
      teacherCompensationType: "fixed",
      teacherCompensationValue: 1500,
      subscriptionId: null,
      trial: false,
      validationState: snapshotState,
    },
  });

  const errorResponse = (
    action: () => unknown,
  ): Record<string, unknown> => {
    try {
      action();
    } catch (error) {
      expect(error).toBeInstanceOf(UnprocessableEntityException);
      return (error as UnprocessableEntityException).getResponse() as Record<
        string,
        unknown
      >;
    }
    throw new Error("Expected validation to fail.");
  };

  it("keeps update validation errors in command precedence order", () => {
    const cases = [
      {
        dto: { force: true, status: "completed" },
        existing: { ...existingLesson(), snapshot: null },
        expected: {
          code: "CONSTRAINT_OVERRIDE_NOT_ALLOWED",
          message: "Legacy force bypass is not allowed.",
          fields: ["force"],
        },
      },
      {
        dto: {
          status: "scheduled",
          clientRef: { type: "lead" as const, id: "lead-b" },
        },
        existing: { ...existingLesson(), snapshot: null },
        expected: {
          code: "MANUAL_LESSON_LIFECYCLE_FORBIDDEN",
          message: "Lesson lifecycle is server-managed.",
          fields: ["status"],
        },
      },
      {
        dto: { clientRef: { type: "lead" as const, id: "lead-b" } },
        existing: existingLesson("legacy_incomplete"),
        expected: {
          code: "LESSON_SNAPSHOT_INCOMPLETE",
          message: "Lesson requires a valid immutable snapshot before editing.",
          fields: ["snapshot"],
        },
      },
      {
        dto: {
          clientRef: { type: "lead" as const, id: "lead-b" },
          completionType: " standard.cancelled ",
          isTrial: true,
          clientChargeType: "subscription" as const,
          clientChargeValue: 1000,
          subscriptionId: "subscription-b",
          teacherCompensationType: "hourly" as const,
          teacherCompensationValue: 2000,
          teacherRate: 2000,
        },
        existing: existingLesson(),
        expected: {
          code: "IMMUTABLE_LESSON_SNAPSHOT",
          message: "Lesson financial/completion snapshot is immutable.",
          fields: [
            "clientChargeType",
            "clientChargeValue",
            "clientRef",
            "completionType",
            "isTrial",
            "subscriptionId",
            "teacherCompensationType",
            "teacherCompensationValue",
            "teacherRate",
          ],
        },
      },
    ];

    for (const testCase of cases) {
      expect(
        errorResponse(() => validator.update(testCase.dto, testCase.existing)),
      ).toEqual(testCase.expected);
    }
  });

  it("coerces an update from mutable fields and the immutable snapshot", () => {
    expect(
      validator.update(
        {
          notes: " updated note ",
          scheduledAt: "2026-08-27T10:30:00+03:00",
          durationMinutes: 45,
        },
        existingLesson(),
      ),
    ).toEqual({
      clientRef: { type: "student", id: "student-a" },
      teacherId: "teacher-a",
      branchId: "branch-a",
      roomId: "room-a",
      scheduledAt: "2026-08-27T07:30:00.000Z",
      durationMinutes: 45,
      endAt: "2026-08-27T08:15:00.000Z",
      isTrial: false,
      notes: "updated note",
      completionType: "standard.success",
      clientChargeType: "none",
      clientChargeValue: 0,
      teacherCompensationType: "fixed",
      teacherCompensationValue: 1500,
      subscriptionId: null,
    });
  });
});
