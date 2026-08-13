/**
 * Shared CRM row shapes + row→DTO mappers.
 *
 * Before this module the same `LessonRow`/`toLessonDto`, `TaskRow`/`toTaskDto`,
 * `TimelineRow`/`toTimelineDto` and `PaymentRow`/`toPaymentDto` lived byte-for-byte
 * in 2–3 services each (CrmService, LeadsService, ScheduleService,
 * TimelineService, FinanceService), so a change to a DTO shape meant editing every
 * copy. They are pure functions (no `this`), so the extraction is behaviour-preserving:
 * every service now imports the single definition here.
 *
 * The presentable-email helpers and the Moscow lesson-time formatter were likewise
 * duplicated and are consolidated here for the same reason.
 */

export interface LessonRow {
  id: string;
  version?: number | string;
  lifecycle_state?: string;
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
  applied_teacher_rate?: string | number | null;
  /**
   * Сумма платежей, привязанных к этому занятию. `null` — платежа за этот день
   * нет (или роль его не видит), и это НЕ то же самое, что «оплачено 0».
   */
  paid_amount?: string | number | null;
  student_user_id: string | null;
  teacher_user_id: string | null;
  student_name: string | null;
  /** Имя лида для пробного занятия без ученика (иначе рисуется «Не назначен»). */
  lead_name?: string | null;
  teacher_name: string | null;
  branch_name: string | null;
  room_name: string | null;
  group_name: string | null;
  group_price_per_lesson: string | null;
  completion_type?: string | null;
  client_charge_type?: string | null;
  client_charge_value?: string | number | null;
  teacher_compensation_type?: string | null;
  teacher_compensation_value?: string | number | null;
  settlement_type_key?: string | null;
  teacher_compensation_rule_key?: string | null;
  teacher_compensation_value_minor?: string | null;
  subscription_id?: string | null;
  snapshot_trial?: boolean | null;
  snapshot_validation_state?: string | null;
  reservation_state?: string | null;
  settlement_failure_code?: string | null;
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
  priority?: string;
  due_at: Date | string | null;
  due_all_day?: boolean;
  created_by: string | null;
  created_at: Date | string;
}

export interface TaskHistoryRow {
  id: string;
  field: string;
  old_value: string | null;
  new_value: string | null;
  changed_at: Date | string;
  source: string;
  changed_by: string | null;
  author_profile_id: string | null;
  author_first_name: string | null;
  author_last_name: string | null;
  old_user_id: string | null;
  old_user_first_name: string | null;
  old_user_last_name: string | null;
  new_user_id: string | null;
  new_user_first_name: string | null;
  new_user_last_name: string | null;
  // Present only in the retained legacy-history projection.
  task_id?: string;
  task_title?: string | null;
  task_entity_type?: string | null;
  task_entity_id?: string | null;
}

/** One field-level change from the legacy task import payload. */
export interface TaskChange {
  field: string;
  oldValue: string | null;
  newValue: string | null;
  oldUserId?: string | null;
  newUserId?: string | null;
}

const toIsoOrNull = (value: Date | string | null): string | null => {
  if (value === null || value === undefined) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? String(value) : date.toISOString();
};

/**
 * Field-level diff between a task before and after an update, in the shape the
 * AmoCRM-style feed renders. Only actually-changed fields produce a row: the
 * PATCH is a coalesce-update, so an unmentioned field arrives as null and must
 * not be logged as «изменено на пусто».
 */
export function diffTaskRows(before: TaskRow, after: TaskRow): TaskChange[] {
  const changes: TaskChange[] = [];

  if (before.status !== after.status) {
    changes.push({
      field: "status",
      oldValue: before.status,
      newValue: after.status,
    });
  }

  if ((before.priority ?? null) !== (after.priority ?? null)) {
    changes.push({
      field: "priority",
      oldValue: before.priority ?? null,
      newValue: after.priority ?? null,
    });
  }

  // Compared as instants, not strings: the same moment can arrive as a Date
  // from one driver path and an ISO string from another, and a string compare
  // would log a phantom reschedule.
  const dueBefore = toIsoOrNull(before.due_at);
  const dueAfter = toIsoOrNull(after.due_at);
  if (dueBefore !== dueAfter) {
    changes.push({ field: "due_at", oldValue: dueBefore, newValue: dueAfter });
  }

  if (before.assigned_to !== after.assigned_to) {
    changes.push({
      field: "assigned_to",
      // Names are NOT frozen here — the feed joins profiles at read time, so a
      // later rename reads correctly in old events.
      oldValue: null,
      newValue: null,
      oldUserId: before.assigned_to,
      newUserId: after.assigned_to,
    });
  }

  if (before.title !== after.title) {
    changes.push({
      field: "title",
      oldValue: before.title,
      newValue: after.title,
    });
  }

  if ((before.description ?? null) !== (after.description ?? null)) {
    changes.push({
      field: "description",
      oldValue: before.description ?? null,
      newValue: after.description ?? null,
    });
  }

  if (
    before.entity_type !== after.entity_type ||
    before.entity_id !== after.entity_id
  ) {
    changes.push({
      field: "entity",
      oldValue: `${before.entity_type}:${before.entity_id}`,
      newValue: `${after.entity_type}:${after.entity_id}`,
    });
  }

  return changes;
}

export function toTaskHistoryDto(row: TaskHistoryRow) {
  const name = (first: string | null, last: string | null) =>
    `${first ?? ""} ${last ?? ""}`.trim() || null;
  const entry: Record<string, unknown> = {
    id: row.id,
    field: row.field,
    oldValue: row.old_value,
    newValue: row.new_value,
    changedAt:
      row.changed_at instanceof Date
        ? row.changed_at.toISOString()
        : row.changed_at,
    source: row.source,
    changedBy: row.changed_by,
    authorProfileId: row.author_profile_id,
    authorName: name(row.author_first_name, row.author_last_name),
    oldUserId: row.old_user_id,
    oldUserName: name(row.old_user_first_name, row.old_user_last_name),
    newUserId: row.new_user_id,
    newUserName: name(row.new_user_first_name, row.new_user_last_name),
  };
  if (row.task_id) {
    entry.taskId = row.task_id;
    entry.taskTitle = row.task_title ?? null;
    entry.taskEntityType = row.task_entity_type ?? null;
    entry.taskEntityId = row.task_entity_id ?? null;
  }
  return entry;
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
  /** Занятие, за которое пришёл платёж. NULL — платёж не разнесён по занятиям. */
  lesson_id?: string | null;
}

export function toLessonDto(row: LessonRow) {
  return {
    id: row.id,
    version:
      row.version === null || row.version === undefined
        ? null
        : Number(row.version),
    lifecycleState: row.lifecycle_state ?? null,
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
    // The rate actually paid for this lesson (lesson → group → history → 0),
    // as opposed to teacherRate above, which is only the per-lesson override.
    // null = the caller may not see pay data; see listLessons.
    appliedTeacherRate:
      row.applied_teacher_rate === null ||
      row.applied_teacher_rate === undefined
        ? null
        : Number(row.applied_teacher_rate),
    // «Оплаты по дням»: сколько пришло за этот день. null — платежа за него
    // нет, и это не «оплачено 0»: привязывать платёж к занятию не обязательно.
    paidAmount:
      row.paid_amount === null || row.paid_amount === undefined
        ? null
        : Number(row.paid_amount),
    studentName: row.student_name || null,
    leadName: row.lead_name || null,
    teacherName: row.teacher_name || null,
    branchName: row.branch_name || null,
    roomName: row.room_name || null,
    groupName: row.group_name || null,
    groupPricePerLesson:
      row.group_price_per_lesson === null
        ? null
        : Number(row.group_price_per_lesson),
    completionType: row.completion_type ?? null,
    clientChargeType: row.client_charge_type ?? null,
    clientChargeValue:
      row.client_charge_value === null ||
      row.client_charge_value === undefined
        ? null
        : Number(row.client_charge_value),
    teacherCompensationType: row.teacher_compensation_type ?? null,
    teacherCompensationValue:
      row.teacher_compensation_value === null ||
      row.teacher_compensation_value === undefined
        ? null
        : Number(row.teacher_compensation_value),
    settlementTypeKey: row.settlement_type_key ?? null,
    teacherCompensationRuleKey: row.teacher_compensation_rule_key ?? null,
    teacherCompensationValueMinor: row.teacher_compensation_value_minor ?? null,
    subscriptionId: row.subscription_id ?? null,
    snapshotTrial: row.snapshot_trial ?? null,
    snapshotValidationState: row.snapshot_validation_state ?? null,
    reservationState: row.reservation_state ?? null,
    settlementFailureCode: row.settlement_failure_code ?? null,
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
    // Default so a row from a query that doesn't select priority (the client
    // self-view) still hands the UI a usable value.
    priority: row.priority ?? "medium",
    dueAt: row.due_at,
    dueAllDay: row.due_all_day ?? false,
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

/** One edited field, as stored in audit_events.metadata.changes. */
export interface FieldChange {
  field: string;
  from: string | null;
  to: string | null;
}

/**
 * Fields recorded as "changed" without their values.
 *
 * AuditService pipes metadata through redactSensitive, which masks e-mail
 * values inside strings (152-ФЗ). Storing them anyway would render as
 * «Почта: [EMAIL] → [EMAIL]» — noise dressed up as an audit trail. So the
 * change is recorded as a fact and the UI says «Почта изменена».
 *
 * Name/phone are NOT here: redactSensitive masks by KEY, and these live under
 * neutral keys (field/from/to), so their values survive — which is exactly what
 * the customer asked for («правки полей — телефон, имя, дисциплина»).
 */
const VALUELESS_AUDIT_FIELDS = new Set(["email"]);

const toAuditScalar = (value: unknown): string | null => {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "object") return JSON.stringify(value);
  const text = String(value);
  return text.length === 0 ? null : text;
};

/**
 * Field-level diff for the client-card history: which fields an edit actually
 * touched, old → new. Both leads and students are coalesce-updates, so an
 * unmentioned field arrives as null and must not read as «стёрли значение».
 *
 * custom_data is diffed per KEY rather than as a blob: «Уровень: A1 → A2» is
 * an audit entry, a jsonb dump is not.
 */
export function diffEntityFields(
  before: Record<string, unknown>,
  after: Record<string, unknown>,
  fields: string[],
): FieldChange[] {
  const changes: FieldChange[] = [];
  for (const field of fields) {
    const from = toAuditScalar(before[field]);
    const to = toAuditScalar(after[field]);
    if (from === to) continue;
    changes.push(
      VALUELESS_AUDIT_FIELDS.has(field)
        ? { field, from: null, to: null }
        : { field, from, to },
    );
  }

  const beforeCustom = (before.custom_data ?? {}) as Record<string, unknown>;
  const afterCustom = (after.custom_data ?? {}) as Record<string, unknown>;
  const keys = new Set([
    ...Object.keys(beforeCustom),
    ...Object.keys(afterCustom),
  ]);
  for (const key of [...keys].sort()) {
    const from = toAuditScalar(beforeCustom[key]);
    const to = toAuditScalar(afterCustom[key]);
    if (from === to) continue;
    changes.push({ field: `custom_data.${key}`, from, to });
  }
  return changes;
}

/** Russian labels for audited fields; unknown keys fall back to the raw name. */
const AUDIT_FIELD_LABELS: Record<string, string> = {
  first_name: "Имя",
  last_name: "Фамилия",
  phone: "Телефон",
  email: "Почта",
  source: "Источник",
  notes: "Заметки",
  status_id: "Статус",
  assigned_to: "Ответственный",
  branch_id: "Филиал",
  status: "Статус",
  "custom_data.birthday": "Дата рождения",
  "custom_data.gender": "Пол",
  "custom_data.level": "Уровень",
  "custom_data.category": "Категория",
  "custom_data.disciplines": "Дисциплины",
  "custom_data.adSource": "Рекламный источник",
  "custom_data.middleName": "Отчество",
};

const auditFieldLabel = (field: string): string =>
  AUDIT_FIELD_LABELS[field] ??
  (field.startsWith("custom_data.") ? field.slice("custom_data.".length) : field);

/**
 * Turns an audit row into something a human reads. The timeline hands us
 * metadata as raw JSON text in `body`; rendering that verbatim in the client
 * card would put `{"changes":[{"field":"phone",...}]}` on screen.
 */
function describeAuditRow(row: TimelineRow): { title: string; body: string | null } {
  const fallbackTitle = row.title;
  let parsed: unknown = null;
  try {
    parsed = row.body ? JSON.parse(row.body) : null;
  } catch {
    // Not JSON (or truncated) — leave the row as the raw action name.
    return { title: fallbackTitle, body: row.body };
  }
  const changes = (parsed as { changes?: FieldChange[] } | null)?.changes;
  if (!Array.isArray(changes) || changes.length === 0) {
    // An audited action with no diff (created/deleted) — keep the action name,
    // drop the empty jsonb so it does not render as "{}".
    return { title: fallbackTitle, body: null };
  }
  const lines = changes.map((change) => {
    const label = auditFieldLabel(change.field);
    if (change.from === null && change.to === null) return `${label}: изменено`;
    return `${label}: ${change.from ?? "—"} → ${change.to ?? "—"}`;
  });
  return { title: "Правка полей", body: lines.join("\n") };
}

export function toTimelineDto(row: TimelineRow) {
  const actorName =
    `${row.actor_first_name ?? ""} ${row.actor_last_name ?? ""}`.trim();
  const { title, body } =
    row.type === "audit"
      ? describeAuditRow(row)
      : { title: row.title, body: row.body };
  return {
    id: row.id,
    type: row.type,
    title,
    body,
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
    lessonId: row.lesson_id ?? null,
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
