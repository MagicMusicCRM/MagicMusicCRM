import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import type {
  CompleteLessonDraft,
  ExistingLessonDraft,
  LessonClientRefType,
  LessonDraftInput,
} from "./lesson-draft.contracts";

export type {
  CompleteLessonDraft,
  ExistingLessonDraft,
} from "./lesson-draft.contracts";

@Injectable()
export class LessonRequiredFieldValidator {
  create(dto: LessonDraftInput): CompleteLessonDraft {
    if (dto.force === true) {
      this.fail(
        "CONSTRAINT_OVERRIDE_NOT_ALLOWED",
        ["force"],
        "Legacy force bypass is not allowed.",
      );
    }
    if (dto.status !== undefined && dto.status !== "scheduled") {
      this.fail(
        "INVALID_LESSON_INITIAL_STATE",
        ["status"],
        "A new lesson must start in scheduled state.",
      );
    }
    const clientRef = this.clientRef(dto);
    const missing = [
      !clientRef ? "clientRef" : null,
      !dto.teacherId ? "teacherId" : null,
      !dto.branchId ? "branchId" : null,
      !dto.roomId ? "roomId" : null,
      !dto.scheduledAt ? "scheduledAt" : null,
      dto.durationMinutes === undefined ? "durationMinutes" : null,
      dto.isTrial === undefined ? "isTrial" : null,
      !dto.completionType?.trim() ? "completionType" : null,
      !dto.clientChargeType ? "clientChargeType" : null,
      dto.clientChargeValue === undefined ? "clientChargeValue" : null,
      !dto.teacherCompensationType ? "teacherCompensationType" : null,
      dto.teacherCompensationValue === undefined
        ? "teacherCompensationValue"
        : null,
    ].filter((field): field is string => field !== null);
    if (missing.length > 0) {
      this.fail(
        "LESSON_REQUIRED_FIELDS",
        missing,
        "Complete lesson draft is required.",
      );
    }
    return this.complete(dto, clientRef!);
  }

  update(
    dto: LessonDraftInput,
    existing: ExistingLessonDraft,
  ): CompleteLessonDraft {
    if (dto.force === true) {
      this.fail(
        "CONSTRAINT_OVERRIDE_NOT_ALLOWED",
        ["force"],
        "Legacy force bypass is not allowed.",
      );
    }
    if (dto.status !== undefined) {
      this.fail(
        "MANUAL_LESSON_LIFECYCLE_FORBIDDEN",
        ["status"],
        "Lesson lifecycle is server-managed.",
      );
    }
    if (!existing.snapshot || existing.snapshot.validationState !== "valid") {
      this.fail(
        "LESSON_SNAPSHOT_INCOMPLETE",
        ["snapshot"],
        "Lesson requires a valid immutable snapshot before editing.",
      );
    }
    const snapshot = existing.snapshot;
    const requestedClient = this.clientRef(dto);
    const immutableChanges = [
      requestedClient &&
      (requestedClient.type !== snapshot.clientType ||
        requestedClient.id !== snapshot.clientId)
        ? "clientRef"
        : null,
      dto.isTrial !== undefined && dto.isTrial !== snapshot.trial
        ? "isTrial"
        : null,
      dto.completionType !== undefined &&
      dto.completionType.trim() !== snapshot.completionType
        ? "completionType"
        : null,
      dto.clientChargeType !== undefined &&
      dto.clientChargeType !== snapshot.clientChargeType
        ? "clientChargeType"
        : null,
      dto.clientChargeValue !== undefined &&
      dto.clientChargeValue !== snapshot.clientChargeValue
        ? "clientChargeValue"
        : null,
      dto.teacherCompensationType !== undefined &&
      dto.teacherCompensationType !== snapshot.teacherCompensationType
        ? "teacherCompensationType"
        : null,
      dto.teacherCompensationValue !== undefined &&
      dto.teacherCompensationValue !== snapshot.teacherCompensationValue
        ? "teacherCompensationValue"
        : null,
      dto.teacherRate !== undefined &&
      dto.teacherRate !== snapshot.teacherCompensationValue
        ? "teacherRate"
        : null,
      dto.subscriptionId !== undefined &&
      dto.subscriptionId !== snapshot.subscriptionId
        ? "subscriptionId"
        : null,
    ].filter((field): field is string => field !== null);
    if (immutableChanges.length > 0) {
      this.fail(
        "IMMUTABLE_LESSON_SNAPSHOT",
        immutableChanges,
        "Lesson financial/completion snapshot is immutable.",
      );
    }
    return this.complete(
      {
        ...dto,
        clientRef: {
          type: snapshot.clientType,
          id: snapshot.clientId,
        },
        teacherId: dto.teacherId ?? existing.teacherId ?? undefined,
        branchId: dto.branchId ?? existing.branchId ?? undefined,
        roomId: dto.roomId ?? existing.roomId ?? undefined,
        scheduledAt:
          dto.scheduledAt ?? new Date(existing.scheduledAt).toISOString(),
        durationMinutes:
          dto.durationMinutes ?? existing.durationMinutes,
        isTrial: snapshot.trial,
        notes: dto.notes ?? existing.notes ?? undefined,
        completionType: snapshot.completionType,
        clientChargeType: snapshot.clientChargeType,
        clientChargeValue: snapshot.clientChargeValue,
        teacherCompensationType: snapshot.teacherCompensationType,
        teacherCompensationValue: snapshot.teacherCompensationValue,
        subscriptionId: snapshot.subscriptionId ?? undefined,
      },
      {
        type: snapshot.clientType,
        id: snapshot.clientId,
      },
    );
  }

  private complete(
    dto: LessonDraftInput,
    clientRef: { type: LessonClientRefType; id: string },
  ): CompleteLessonDraft {
    const missingResources = [
      !dto.teacherId ? "teacherId" : null,
      !dto.branchId ? "branchId" : null,
      !dto.roomId ? "roomId" : null,
    ].filter((field): field is string => field !== null);
    if (missingResources.length > 0) {
      this.fail(
        "LESSON_REQUIRED_FIELDS",
        missingResources,
        "Complete lesson resources are required.",
      );
    }
    const startsAt = new Date(dto.scheduledAt!);
    const endAt = new Date(
      startsAt.getTime() + dto.durationMinutes! * 60_000,
    );
    if (
      !Number.isFinite(startsAt.getTime()) ||
      !Number.isFinite(endAt.getTime()) ||
      startsAt >= endAt
    ) {
      this.fail(
        "INVALID_INTERVAL",
        ["scheduledAt", "durationMinutes"],
        "Lesson interval is invalid.",
      );
    }
    const subscriptionId = dto.subscriptionId ?? null;
    if (
      (dto.clientChargeType === "subscription" && !subscriptionId) ||
      (dto.clientChargeType !== "subscription" && subscriptionId)
    ) {
      this.fail(
        "INVALID_FINANCIAL_SNAPSHOT",
        ["clientChargeType", "subscriptionId"],
        "Subscription reference must match the charge type.",
      );
    }
    return {
      clientRef,
      teacherId: dto.teacherId!,
      branchId: dto.branchId!,
      roomId: dto.roomId!,
      scheduledAt: startsAt.toISOString(),
      durationMinutes: dto.durationMinutes!,
      endAt: endAt.toISOString(),
      isTrial: dto.isTrial!,
      notes: dto.notes?.trim() || null,
      completionType: dto.completionType!.trim(),
      clientChargeType: dto.clientChargeType!,
      clientChargeValue: dto.clientChargeValue!,
      teacherCompensationType: dto.teacherCompensationType!,
      teacherCompensationValue: dto.teacherCompensationValue!,
      subscriptionId,
    };
  }

  private clientRef(
    dto: LessonDraftInput,
  ): { type: LessonClientRefType; id: string } | null {
    if (dto.clientRef) return dto.clientRef;
    if (dto.studentId && !dto.leadId && !dto.groupId) {
      return { type: "student", id: dto.studentId };
    }
    if (dto.leadId && !dto.studentId && !dto.groupId) {
      return { type: "lead", id: dto.leadId };
    }
    return null;
  }

  private fail(code: string, fields: string[], message: string): never {
    throw new UnprocessableEntityException({
      code,
      message,
      fields: [...new Set(fields)].sort(),
    });
  }
}
