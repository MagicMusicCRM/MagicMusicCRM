import { UnprocessableEntityException } from "@nestjs/common";
import type { LessonDraftInput } from "./lesson-draft.contracts";
import type {
  GroupLessonDraft,
  TransitionSource,
} from "./lesson-transition.types";

export function groupTransitionSuccessorDraft(
  dto: LessonDraftInput,
  source: TransitionSource,
): GroupLessonDraft {
  const snapshot = validSnapshot(source);
  const immutableChanges = [
    ...subjectChanges(dto, source),
    ...financialChanges(dto),
    ...compensationChanges(dto, snapshot),
    ...controlChanges(dto, snapshot),
  ];
  if (immutableChanges.length > 0) {
    invalidGroupDraft("IMMUTABLE_LESSON_SNAPSHOT", immutableChanges);
  }
  const resources = groupResources(dto, source);
  const interval = groupInterval(dto, source);
  return {
    kind: "group",
    groupId: source.groupId!,
    ...resources,
    ...interval,
    isTrial: snapshot.trial,
    notes: dto.notes === undefined ? source.notes : dto.notes.trim() || null,
    completionType: snapshot.completionType,
    teacherCompensationType: snapshot.teacherCompensationType,
    teacherCompensationValue: snapshot.teacherCompensationValue,
    participants: source.participants,
  };
}

function validSnapshot(source: TransitionSource) {
  const snapshot = source.groupSnapshot;
  if (!snapshot || snapshot.validationState !== "valid") {
    invalidGroupDraft("LESSON_SNAPSHOT_INCOMPLETE", ["snapshot"]);
  }
  return snapshot;
}

function groupResources(dto: LessonDraftInput, source: TransitionSource) {
  const teacherId = dto.teacherId ?? source.teacherId;
  const branchId = dto.branchId ?? source.branchId;
  const roomId = dto.roomId ?? source.roomId;
  const missing = [
    !teacherId ? "teacherId" : null,
    !branchId ? "branchId" : null,
    !roomId ? "roomId" : null,
  ].filter((field): field is string => field !== null);
  if (missing.length > 0) invalidGroupDraft("LESSON_REQUIRED_FIELDS", missing);
  return { teacherId: teacherId!, branchId: branchId!, roomId: roomId! };
}

function groupInterval(dto: LessonDraftInput, source: TransitionSource) {
  const start = new Date(dto.scheduledAt ?? source.scheduledAt);
  const durationMinutes = dto.durationMinutes ?? source.durationMinutes;
  const end = new Date(start.getTime() + durationMinutes * 60_000);
  if (!Number.isFinite(start.getTime()) || start >= end) {
    invalidGroupDraft("INVALID_INTERVAL", ["scheduledAt", "durationMinutes"]);
  }
  return {
    scheduledAt: start.toISOString(),
    durationMinutes,
    endAt: end.toISOString(),
  };
}

function subjectChanges(dto: LessonDraftInput, source: TransitionSource) {
  return [
    dto.clientRef || dto.studentId || dto.leadId ? "clientRef" : null,
    dto.groupId !== undefined && dto.groupId !== source.groupId
      ? "groupId"
      : null,
    dto.status !== undefined ? "status" : null,
  ].filter((field): field is string => field !== null);
}

function financialChanges(dto: LessonDraftInput) {
  return [
    dto.clientChargeType !== undefined && dto.clientChargeType !== "none"
      ? "clientChargeType"
      : null,
    dto.clientChargeValue !== undefined && dto.clientChargeValue !== 0
      ? "clientChargeValue"
      : null,
    dto.subscriptionId !== undefined ? "subscriptionId" : null,
  ].filter((field): field is string => field !== null);
}

function compensationChanges(
  dto: LessonDraftInput,
  snapshot: NonNullable<TransitionSource["groupSnapshot"]>,
) {
  return [
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
  ].filter((field): field is string => field !== null);
}

function controlChanges(
  dto: LessonDraftInput,
  snapshot: NonNullable<TransitionSource["groupSnapshot"]>,
) {
  return [
    dto.isTrial !== undefined && dto.isTrial !== snapshot.trial
      ? "isTrial"
      : null,
    dto.completionType !== undefined &&
    dto.completionType.trim() !== snapshot.completionType
      ? "completionType"
      : null,
    dto.force === true ? "force" : null,
  ].filter((field): field is string => field !== null);
}

function invalidGroupDraft(code: string, fields: string[]): never {
  throw new UnprocessableEntityException({
    code,
    fields: [...new Set(fields)].sort(),
  });
}
