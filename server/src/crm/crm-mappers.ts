/**
 * Shared CRM row shapes + row→DTO mappers.
 *
 * Before this module the same `LessonRow`/`toLessonDto`, `TaskRow`/`toTaskDto`,
 * `TimelineRow`/`toTimelineDto` and `PaymentRow`/`toPaymentDto` lived byte-for-byte
 * in 2–3 services each (CrmService, LeadsService, ScheduleService, TasksService,
 * TimelineService, FinanceService), so a change to a DTO shape meant editing every
 * copy. They are pure functions (no `this`), so the extraction is behaviour-preserving:
 * every service now imports the single definition here.
 *
 * The presentable-email helpers and the Moscow lesson-time formatter were likewise
 * duplicated and are consolidated here for the same reason.
 */

export interface LessonRow {
  id: string;
  student_id: string | null;
  group_id: string | null;
  lead_id: string | null;
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  scheduled_at: Date | string;
  duration_minutes: number;
  status: string;
  is_trial: boolean;
  notes: string | null;
  teacher_rate?: string | number | null;
  student_user_id: string | null;
  teacher_user_id: string | null;
  student_name: string | null;
  teacher_name: string | null;
  branch_name: string | null;
  room_name: string | null;
  group_name: string | null;
  group_price_per_lesson: string | null;
}

export interface TaskRow {
  id: string;
  entity_type: string;
  entity_id: string;
  assigned_to: string | null;
  assigned_first_name?: string | null;
  assigned_last_name?: string | null;
  creator_first_name?: string | null;
  creator_last_name?: string | null;
  assigned_profile_id?: string | null;
  creator_profile_id?: string | null;
  entity_first_name?: string | null;
  entity_last_name?: string | null;
  entity_name?: string | null;
  branch_id?: string | null;
  branch_name?: string | null;
  title: string;
  description: string | null;
  status: string;
  due_at: Date | string | null;
  created_by: string | null;
  created_at: Date | string;
}

export interface TimelineRow {
  id: string;
  type: string;
  title: string;
  body: string | null;
  status: string | null;
  amount: string | number | null;
  actor_user_id: string | null;
  actor_first_name: string | null;
  actor_last_name: string | null;
  occurred_at: Date | string;
}

export interface PaymentRow {
  id: string;
  student_id: string;
  student_user_id: string | null;
  student_first_name: string | null;
  student_last_name: string | null;
  amount: string;
  currency: string;
  payment_date: Date | string;
  method: string | null;
  external_id: string | null;
  notes: string | null;
  created_by: string | null;
  created_at: Date | string;
}

export function toLessonDto(row: LessonRow) {
  return {
    id: row.id,
    studentId: row.student_id,
    groupId: row.group_id,
    leadId: row.lead_id,
    teacherId: row.teacher_id,
    branchId: row.branch_id,
    roomId: row.room_id,
    scheduledAt: row.scheduled_at,
    durationMinutes: row.duration_minutes,
    status: row.status,
    isTrial: row.is_trial,
    notes: row.notes,
    teacherRate:
      row.teacher_rate === null || row.teacher_rate === undefined
        ? null
        : Number(row.teacher_rate),
    studentName: row.student_name || null,
    teacherName: row.teacher_name || null,
    branchName: row.branch_name || null,
    roomName: row.room_name || null,
    groupName: row.group_name || null,
    groupPricePerLesson:
      row.group_price_per_lesson === null
        ? null
        : Number(row.group_price_per_lesson),
  };
}

export function toTaskDto(row: TaskRow) {
  const assignedName =
    `${row.assigned_first_name ?? ""} ${row.assigned_last_name ?? ""}`.trim();
  const creatorName =
    `${row.creator_first_name ?? ""} ${row.creator_last_name ?? ""}`.trim();
  const personName =
    `${row.entity_first_name ?? ""} ${row.entity_last_name ?? ""}`.trim();
  const task: Record<string, unknown> = {
    id: row.id,
    entityType: row.entity_type,
    entityId: row.entity_id,
    assignedTo: row.assigned_to,
    assignedName: assignedName || null,
    assignedProfileId: row.assigned_profile_id ?? null,
    creatorProfileId: row.creator_profile_id ?? null,
    entityName: personName || row.entity_name?.trim() || null,
    title: row.title,
    description: row.description,
    status: row.status,
    dueAt: row.due_at,
    createdBy: row.created_by,
    createdAt: row.created_at,
  };
  if (
    row.creator_first_name !== undefined ||
    row.creator_last_name !== undefined
  ) {
    task.creatorName = creatorName || null;
  }
  if (row.branch_id !== undefined) {
    task.branchId = row.branch_id;
  }
  if (row.branch_name !== undefined) {
    task.branchName = row.branch_name;
  }
  return task;
}

export function toTimelineDto(row: TimelineRow) {
  const actorName =
    `${row.actor_first_name ?? ""} ${row.actor_last_name ?? ""}`.trim();
  return {
    id: row.id,
    type: row.type,
    title: row.title,
    body: row.body,
    status: row.status,
    amount: row.amount === null ? null : Number(row.amount),
    actorUserId: row.actor_user_id,
    actorName: actorName || null,
    occurredAt: row.occurred_at,
  };
}

export function toPaymentDto(row: PaymentRow) {
  return {
    id: row.id,
    studentId: row.student_id,
    studentName:
      `${row.student_first_name ?? ""} ${row.student_last_name ?? ""}`.trim() ||
      null,
    amount: Number(row.amount),
    currency: row.currency,
    paymentDate: row.payment_date,
    method: row.method,
    externalId: row.external_id,
    notes: row.notes,
    createdBy: row.created_by,
    createdAt: row.created_at,
  };
}

/**
 * Import placeholders (hollihop-client-*@migration.invalid etc.) are real
 * students/leads without a HolliHop email. `isDeliverableEmail` hides the fake
 * address from the UI instead of showing noise — the record is never deleted.
 */
export function isDeliverableEmail(value: string): boolean {
  const email = value.trim().toLowerCase();
  return (
    email.length > 0 &&
    !email.endsWith("@local.magicmusiccrm.invalid") &&
    !email.endsWith("@migration.invalid")
  );
}

export function presentableEmail(
  value: string | null | undefined,
): string | null {
  return value && isDeliverableEmail(value) ? value : null;
}

/** Reminder-style Moscow-local lesson time ("DD.MM HH24:MI"). */
export function formatLessonTimeMoscow(value: Date | string | null): string {
  if (value === null) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const parts = new Intl.DateTimeFormat("ru-RU", {
    timeZone: "Europe/Moscow",
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(date);
  const get = (type: string) =>
    parts.find((part) => part.type === type)?.value ?? "";
  return `${get("day")}.${get("month")} ${get("hour")}:${get("minute")}`;
}
