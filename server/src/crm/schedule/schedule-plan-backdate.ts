import {
  ConflictException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import type { PoolClient } from "pg";
import type {
  SchedulePlanParticipantDto,
  SchedulePlanRowDto,
  UpdateSchedulePlanDto,
} from "../dto/schedule-plan.dto";
import type {
  LockedSchedulePlan,
  SchedulePlanRepository,
  SchedulePlanSeriesSnapshot,
} from "./schedule-plan.repository";

export type SchedulePlanUpdateMode =
  "replace_from" | "extend_backwards" | "move_start_forward";

const rejectShapeChange = (): never => {
  throw new UnprocessableEntityException({
    code: "SCHEDULE_PLAN_BACKDATE_SHAPE_CHANGE",
    fields: ["activeFrom", "rows", "subscriptionId", "participants"],
  });
};

export const initialSchedulePlanUpdateMode = (
  plan: LockedSchedulePlan,
  effectiveFrom: string,
): SchedulePlanUpdateMode =>
  effectiveFrom < plan.active_from ? "extend_backwards" : "replace_from";

export const previousScheduleDate = (value: string): string => {
  const date = new Date(`${value.slice(0, 10)}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() - 1);
  return date.toISOString().slice(0, 10);
};

const participantFingerprint = (participants: SchedulePlanParticipantDto[]) =>
  fingerprintPayload(
    participants
      .map(({ studentId, subscriptionId }) => ({ studentId, subscriptionId }))
      .sort(
        (left, right) =>
          left.studentId.localeCompare(right.studentId) ||
          left.subscriptionId.localeCompare(right.subscriptionId),
      ),
  );

const effectiveDecision = (
  row: SchedulePlanRowDto,
  stored: SchedulePlanSeriesSnapshot,
) => {
  if (!stored.planned_financial_decision) return null;
  const requested = row.financialDecision;
  const decision = stored.planned_financial_decision!;
  return {
    ...requested,
    clientDecisions:
      requested.clientDecisions ?? decision.clientDecisions,
    teacherCompensationRuleKey:
      requested.teacherCompensationRuleKey ??
      decision.teacherCompensationRuleKey,
    teacherCompensationValueMinor:
      requested.teacherCompensationValueMinor ??
      decision.teacherCompensationValueMinor,
    teacherCreditedDurationMinutes:
      requested.teacherCreditedDurationMinutes ??
      decision.teacherCreditedDurationMinutes,
    teacherCompensationSource:
      requested.teacherCompensationSource ??
      decision.teacherCompensationSource,
  };
};

const rowFingerprint = (
  row: SchedulePlanRowDto,
  stored: SchedulePlanSeriesSnapshot,
) =>
  fingerprintPayload({
    teacherId: row.teacherId,
    roomId: row.roomId,
    branchId: row.branchId,
    weekday: row.weekday,
    beginTime: row.beginTime.slice(0, 5),
    durationMinutes: row.durationMinutes ?? 60,
    notes: row.notes?.trim() || null,
    financialDecision: effectiveDecision(row, stored),
  });

const storedRowFingerprint = (stored: SchedulePlanSeriesSnapshot) =>
  fingerprintPayload({
    teacherId: stored.teacher_id,
    roomId: stored.room_id,
    branchId: stored.branch_id,
    weekday: Number(stored.weekday),
    beginTime: stored.begin_time.slice(0, 5),
    durationMinutes: Number(stored.duration_minutes),
    notes: stored.notes?.trim() || null,
    financialDecision: stored.planned_financial_decision,
  });

export const assertSchedulePlanBackdateShape = (input: {
  plan: LockedSchedulePlan;
  dto: UpdateSchedulePlanDto;
  subscriptionId: string | null;
  activeUntil: string | null;
  participants: SchedulePlanParticipantDto[];
  participantsAtOldStart: SchedulePlanParticipantDto[];
  activeSeries: SchedulePlanSeriesSnapshot[];
}): void => {
  if (!schedulePlanBusinessShapeMatches(input)) rejectShapeChange();
};

export const schedulePlanBusinessShapeMatches = (input: {
  plan: LockedSchedulePlan;
  dto: UpdateSchedulePlanDto;
  subscriptionId: string | null;
  activeUntil: string | null;
  participants: SchedulePlanParticipantDto[];
  participantsAtOldStart: SchedulePlanParticipantDto[];
  activeSeries: SchedulePlanSeriesSnapshot[];
  includeTitle?: boolean;
}): boolean => {
  if (
    input.subscriptionId !== input.plan.subscription_id ||
    input.activeUntil !== input.plan.active_until ||
    (input.includeTitle === true &&
      (input.dto.title?.trim() || input.plan.title) !== input.plan.title) ||
    participantFingerprint(input.participants) !==
      participantFingerprint(input.participantsAtOldStart) ||
    input.dto.rows.length !== input.activeSeries.length
  ) {
    return false;
  }
  const storedById = new Map(
    input.activeSeries.map((series) => [series.id, series]),
  );
  const requestedIds = input.dto.rows.map((row) => row.seriesId);
  if (
    requestedIds.some((id) => !id || !storedById.has(id)) ||
    new Set(requestedIds).size !== input.activeSeries.length
  ) {
    return false;
  }
  return input.dto.rows.every((row) => {
    const stored = storedById.get(row.seriesId!);
    return !(
      !stored ||
      !stored.planned_financial_decision ||
      row.plannedSettlementReason?.trim() ||
      rowFingerprint(row, stored) !== storedRowFingerprint(stored)
    );
  });
};

export const finalizedSchedulePlanUpdateMode = (input: {
  plan: LockedSchedulePlan;
  effectiveFrom: string;
  shapeMatches: boolean;
}): SchedulePlanUpdateMode => {
  if (input.effectiveFrom < input.plan.active_from) return "extend_backwards";
  return input.effectiveFrom > input.plan.active_from && input.shapeMatches
    ? "move_start_forward"
    : "replace_from";
};

export const assertUniqueSchedulePlanParticipants = (
  participants: SchedulePlanParticipantDto[],
): void => {
  if (
    new Set(participants.map((item) => item.studentId)).size !==
    participants.length
  ) {
    throw new UnprocessableEntityException({
      code: "SCHEDULE_PLAN_DUPLICATE_PARTICIPANT",
      fields: ["participants"],
    });
  }
};

export const assertRequestedSchedulePlanSeries = (
  rows: SchedulePlanRowDto[],
  activeSeries: SchedulePlanSeriesSnapshot[],
): void => {
  const activeIds = new Set(activeSeries.map((row) => row.id));
  const requestedIds = rows
    .map((row) => row.seriesId)
    .filter((id): id is string => Boolean(id));
  if (requestedIds.some((id) => !activeIds.has(id))) {
    throw new ConflictException({
      code: "SCHEDULE_PLAN_SERIES_STALE",
      message: "One of the edited rows is no longer active.",
    });
  }
};

export const assertSchedulePlanEditOutsidePrefix = (
  effectiveFrom: string,
  activeSeries: SchedulePlanSeriesSnapshot[],
): void => {
  const firstActiveDate = activeSeries
    .map((series) => series.valid_from)
    .sort()[0];
  if (firstActiveDate && effectiveFrom < firstActiveDate) {
    throw new UnprocessableEntityException({
      code: "SCHEDULE_PLAN_PREFIX_EDIT_UNSUPPORTED",
      fields: ["effectiveFrom"],
    });
  }
};

export const prepareSchedulePlanUpdateMode = async (input: {
  client: PoolClient;
  repository: SchedulePlanRepository;
  planId: string;
  plan: LockedSchedulePlan;
  dto: UpdateSchedulePlanDto;
  effectiveFrom: string;
  subscriptionId: string | null;
  activeUntil: string | null;
  participants: SchedulePlanParticipantDto[];
  participantsAtOldStart: SchedulePlanParticipantDto[];
  activeSeries: SchedulePlanSeriesSnapshot[];
}): Promise<SchedulePlanUpdateMode> => {
  const mode = finalizedSchedulePlanUpdateMode({
    plan: input.plan,
    effectiveFrom: input.effectiveFrom,
    shapeMatches: schedulePlanBusinessShapeMatches({
      ...input,
      includeTitle: true,
    }),
  });
  if (mode === "extend_backwards") {
    assertSchedulePlanBackdateShape(input);
  } else {
    assertSchedulePlanEditOutsidePrefix(
      input.effectiveFrom,
      input.activeSeries,
    );
    if (
      mode === "move_start_forward" &&
      !(await input.repository.isSimpleStartMove(
        input.client,
        input.plan,
        input.activeSeries.map((series) => series.id),
      ))
    ) {
      throw new UnprocessableEntityException({
        code: "SCHEDULE_PLAN_START_MOVE_COMPLEX_HISTORY",
        fields: ["effectiveFrom"],
      });
    }
    if (
      mode === "move_start_forward" &&
      (await input.repository.hasImmutableLessonsInRange(
        input.client,
        input.planId,
        input.plan.active_from,
        input.effectiveFrom,
      ))
    ) {
      throw new UnprocessableEntityException({
        code: "SCHEDULE_PLAN_START_HISTORY_IMMUTABLE",
        fields: ["effectiveFrom"],
      });
    }
    if (
      mode === "replace_from" &&
      (await input.repository.hasTerminalHistoricalLesson(
        input.client,
        input.effectiveFrom,
        input.activeSeries.map((series) => series.id),
      ))
    ) {
      throw new UnprocessableEntityException({
        code: "SCHEDULE_PLAN_TERMINAL_HISTORY_IMMUTABLE",
        fields: ["effectiveFrom"],
      });
    }
  }
  assertRequestedSchedulePlanSeries(input.dto.rows, input.activeSeries);
  return mode;
};
