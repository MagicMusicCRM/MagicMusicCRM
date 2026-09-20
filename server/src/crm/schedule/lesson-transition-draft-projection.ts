import type { TransitionSuccessor } from "./lesson-transition.types";

export const draftProjection = (draft: TransitionSuccessor) => {
  const common = {
    kind: draft.kind,
    teacherId: draft.teacherId,
    branchId: draft.branchId,
    roomId: draft.roomId,
    startAt: draft.scheduledAt,
    durationMinutes: draft.durationMinutes,
    endAt: draft.endAt,
    isTrial: draft.isTrial,
    notes: draft.notes,
    completionType: draft.completionType,
    teacherCompensationType: draft.teacherCompensationType,
    teacherCompensationValue: draft.teacherCompensationValue,
  };
  if (draft.kind === "group") {
    return {
      ...common,
      subject: { type: "group", id: draft.groupId },
      participants: [...draft.participants]
        .sort((left, right) => left.studentId.localeCompare(right.studentId))
        .map((participant) => ({ ...participant })),
    };
  }
  return {
    ...common,
    subject: { type: draft.clientRef.type, id: draft.clientRef.id },
    clientChargeType: draft.clientChargeType,
    clientChargeValue: draft.clientChargeValue,
    subscriptionId: draft.subscriptionId,
  };
};
