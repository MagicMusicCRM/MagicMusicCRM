import { UnprocessableEntityException, ValidationPipe } from "@nestjs/common";
import { UpsertLessonDto } from "../dto/upsert-lesson.dto";
import { assertLessonPatchUsesTransition } from "./lesson-protected-patch.guard";

describe("lesson protected PATCH boundary", () => {
  const pipe = new ValidationPipe({
    transform: true,
    whitelist: true,
    forbidNonWhitelisted: true,
  });
  const parse = (body: Record<string, unknown>): Promise<UpsertLessonDto> =>
    pipe.transform(body, { type: "body", metatype: UpsertLessonDto });

  it.each(["Комментарий", "", null])(
    "allows a notes-only HTTP DTO, including clearing notes (%p)",
    async (notes) => {
      const dto = await parse({ expectedVersion: 1, notes });
      expect(() => assertLessonPatchUsesTransition(dto)).not.toThrow();
    },
  );

  it.each([
    ["teacherId", null],
    ["financialDecision", null],
    ["isTrial", false],
    ["teacherRate", 0],
  ])("still rejects supplied protected %s values (%p)", async (field, value) => {
    const dto = await parse({ expectedVersion: 1, notes: "Комментарий", [field as string]: value });
    expect(() => assertLessonPatchUsesTransition(dto)).toThrow(UnprocessableEntityException);
  });

  it("rejects an HTTP DTO without any note update", async () => {
    const dto = await parse({ expectedVersion: 1 });
    expect(() => assertLessonPatchUsesTransition(dto)).toThrow(UnprocessableEntityException);
  });

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
