import type {
  ScheduleDatedExceptionTimelineEntry,
  SchedulePlanTimelineProjection,
  ScheduleRecurringRuleTimelineEntry,
  ScheduleRuleTimelineChangedField,
  ScheduleRuleTimelineEntry,
} from "./schedule-plan.types";

interface SchedulePlanTimelineResources {
  teacherId: string;
  teacherName: string | null;
  roomId: string;
  roomName: string | null;
  branchId: string;
  branchName: string | null;
  weekday: number;
  beginTime: string;
  durationMinutes: number;
}

export interface SchedulePlanTimelineRuleInput
  extends SchedulePlanTimelineResources {
  id: string;
  activeFrom: string;
  activeUntil: string | null;
}

export interface SchedulePlanTimelineLessonInput
  extends SchedulePlanTimelineResources {
  id: string;
  sourceSeriesId: string;
  seriesId: string | null;
  scheduledAt: string;
  expectedScheduledAt: string;
  scheduledDate: string;
  predecessorId: string | null;
}

export interface SchedulePlanTimelineInput {
  rules: SchedulePlanTimelineRuleInput[];
  lessons: SchedulePlanTimelineLessonInput[];
}

export function buildSchedulePlanTimeline(
  input: SchedulePlanTimelineInput,
  now: Date,
): SchedulePlanTimelineProjection {
  const today = now.toISOString().slice(0, 10);
  const rulesById = new Map(input.rules.map((rule) => [rule.id, rule]));
  const recurringRules = input.rules.map((rule) => recurringEntry(rule, today));
  const exceptions = input.lessons.flatMap((lesson) => {
    const source = rulesById.get(lesson.sourceSeriesId);
    if (!source) return [];
    const changedFields = lessonChanges(lesson, source);
    const isRescheduledSuccessor =
      lesson.seriesId === null || lesson.predecessorId !== null;
    if (changedFields.length === 0 && !isRescheduledSuccessor) return [];
    return [exceptionEntry(lesson, changedFields, today)];
  });
  const entries = [...recurringRules, ...deduplicateExceptions(exceptions)].sort(
    compareTimelineEntries,
  );
  return {
    entries,
    exceptions: entries.filter(
      (entry): entry is ScheduleDatedExceptionTimelineEntry =>
        entry.kind === "dated_exception",
    ),
  };
}

function recurringEntry(
  rule: SchedulePlanTimelineRuleInput,
  today: string,
): ScheduleRecurringRuleTimelineEntry {
  const expired = rule.activeUntil !== null && rule.activeUntil < today;
  const sortBucket: 0 | 1 | 3 = expired
    ? 3
    : rule.activeUntil === null
      ? 0
      : 1;
  const sortAt = expired
    ? rule.activeUntil!
    : rule.activeUntil === null || rule.activeFrom > today
      ? rule.activeFrom
      : rule.activeUntil;
  return {
    ...rule,
    kind: "recurring_rule",
    lessonId: null,
    sourceSeriesId: rule.id,
    status: expired ? "expired" : "active",
    scheduledDate: null,
    changedFields: [],
    sortBucket,
    sortAt,
  };
}

function exceptionEntry(
  lesson: SchedulePlanTimelineLessonInput,
  changedFields: ScheduleRuleTimelineChangedField[],
  today: string,
): ScheduleDatedExceptionTimelineEntry {
  const expired = lesson.scheduledDate < today;
  return {
    id: lesson.id,
    kind: "dated_exception",
    lessonId: lesson.id,
    sourceSeriesId: lesson.sourceSeriesId,
    status: expired ? "expired" : "active",
    activeFrom: lesson.scheduledDate,
    activeUntil: lesson.scheduledDate,
    scheduledDate: lesson.scheduledDate,
    teacherId: lesson.teacherId,
    teacherName: lesson.teacherName,
    roomId: lesson.roomId,
    roomName: lesson.roomName,
    branchId: lesson.branchId,
    branchName: lesson.branchName,
    weekday: lesson.weekday,
    beginTime: lesson.beginTime,
    durationMinutes: lesson.durationMinutes,
    changedFields,
    sortBucket: expired ? 3 : 2,
    sortAt: lesson.scheduledDate,
  };
}

function lessonChanges(
  lesson: SchedulePlanTimelineLessonInput,
  source: SchedulePlanTimelineRuleInput,
): ScheduleRuleTimelineChangedField[] {
  const changed: ScheduleRuleTimelineChangedField[] = [];
  if (timestamp(lesson.scheduledAt) !== timestamp(lesson.expectedScheduledAt)) {
    changed.push("scheduledAt");
  }
  if (lesson.teacherId !== source.teacherId) changed.push("teacherId");
  if (lesson.roomId !== source.roomId) changed.push("roomId");
  if (lesson.branchId !== source.branchId) changed.push("branchId");
  if (lesson.durationMinutes !== source.durationMinutes) {
    changed.push("durationMinutes");
  }
  return changed;
}

function timestamp(value: string): number | string {
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : value;
}

function deduplicateExceptions(
  entries: ScheduleDatedExceptionTimelineEntry[],
): ScheduleDatedExceptionTimelineEntry[] {
  return [...new Map(entries.map((entry) => [entry.id, entry])).values()];
}

function compareTimelineEntries(
  left: ScheduleRuleTimelineEntry,
  right: ScheduleRuleTimelineEntry,
): number {
  if (left.sortBucket !== right.sortBucket) {
    return left.sortBucket - right.sortBucket;
  }
  const byDate = compareText(left.sortAt, right.sortAt);
  if (byDate !== 0) return left.sortBucket === 3 ? -byDate : byDate;
  return compareText(left.id, right.id);
}

function compareText(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}
