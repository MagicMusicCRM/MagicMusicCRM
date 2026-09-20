export type SchedulePlanKind = "individual" | "group";
export type SchedulePlanStatus = "active" | "ended";

export type ScheduleRuleTimelineChangedField =
  | "scheduledAt"
  | "teacherId"
  | "roomId"
  | "branchId"
  | "durationMinutes";

interface ScheduleRuleTimelineEntryBase {
  id: string;
  status: "active" | "expired";
  activeFrom: string;
  activeUntil: string | null;
  scheduledDate: string | null;
  teacherId: string;
  teacherName: string | null;
  roomId: string;
  roomName: string | null;
  branchId: string;
  branchName: string | null;
  weekday: number;
  beginTime: string;
  durationMinutes: number;
  changedFields: ScheduleRuleTimelineChangedField[];
  sortBucket: 0 | 1 | 2 | 3;
  sortAt: string;
}

export interface ScheduleRecurringRuleTimelineEntry
  extends ScheduleRuleTimelineEntryBase {
  kind: "recurring_rule";
  lessonId: null;
  sourceSeriesId: string;
}

export interface ScheduleDatedExceptionTimelineEntry
  extends ScheduleRuleTimelineEntryBase {
  kind: "dated_exception";
  lessonId: string;
  sourceSeriesId: string;
}

export type ScheduleRuleTimelineEntry =
  | ScheduleRecurringRuleTimelineEntry
  | ScheduleDatedExceptionTimelineEntry;

export interface SchedulePlanTimelineProjection {
  entries: ScheduleRuleTimelineEntry[];
  exceptions: ScheduleDatedExceptionTimelineEntry[];
  editableRuleIds: string[];
}

export interface SchedulePlanEntity {
  id: string;
  kind: SchedulePlanKind;
  title: string;
  studentId: string | null;
  groupId: string | null;
  subscriptionId: string | null;
  activeFrom: string;
  activeUntil: string | null;
  status: SchedulePlanStatus;
  version: number;
  endedAt: Date | null;
  endedBy: string | null;
  endReason: string | null;
}

export interface SchedulePlanParticipantEntity {
  id: string;
  planId: string;
  studentId: string;
  subscriptionId: string;
  effectiveFrom: string;
  effectiveUntil: string | null;
  version: number;
}
