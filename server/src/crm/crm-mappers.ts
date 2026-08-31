/**
 * Shared CRM row shapes + row→DTO mappers.
 *
 * Before this module the same `LessonRow`/`toLessonDto`, `TimelineRow`/`toTimelineDto`
 * and `PaymentRow`/`toPaymentDto` lived byte-for-byte
 * in 2–3 services each (CrmService, LeadsService, schedule services,
 * TimelineService, FinanceService), so a change to a DTO shape meant editing every
 * copy. They are pure functions (no `this`), so the extraction is behaviour-preserving:
 * every service now imports the single definition here.
 *
 * The presentable-email helpers and the Moscow lesson-time formatter were likewise
 * duplicated and are consolidated here for the same reason.
 */

import { createSafeAuditChange } from "../audit/audit-field-presentation.policy";
import { AuditPresentationService } from "../audit/audit-presentation.service";
import type { AuditFieldChangeInput } from "../audit/audit-presentation.types";

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

const auditValuesEqual = (from: unknown, to: unknown): boolean => {
  if (from === to) return true;
  if (
    (from === null || from === undefined || from === "") &&
    (to === null || to === undefined || to === "")
  ) return true;
  if (from instanceof Date && to instanceof Date) {
    return from.toISOString() === to.toISOString();
  }
  if (typeof from === "object" && typeof to === "object") {
    return JSON.stringify(from) === JSON.stringify(to);
  }
  return false;
};

const createChangedAuditField = (
  field: string,
  from: unknown,
  to: unknown,
): AuditFieldChangeInput | null => {
  if (auditValuesEqual(from, to)) return null;
  const valueless = VALUELESS_AUDIT_FIELDS.has(field);
  const change = createSafeAuditChange({
    field,
    from: valueless ? null : from,
    to: valueless ? null : to,
  });
  if (!change) return null;
  if (
    !valueless &&
    change.displayMode !== "changed_only" &&
    auditValuesEqual(change.from, change.to)
  ) {
    return change.displayMode === "count"
      ? { ...change, from: null, to: null, displayMode: "changed_only" }
      : null;
  }
  return change;
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
): AuditFieldChangeInput[] {
  const changes: AuditFieldChangeInput[] = [];
  for (const field of fields) {
    const change = createChangedAuditField(field, before[field], after[field]);
    if (change) changes.push(change);
  }

  const beforeCustom = (before.custom_data ?? {}) as Record<string, unknown>;
  const afterCustom = (after.custom_data ?? {}) as Record<string, unknown>;
  const keys = new Set([
    ...Object.keys(beforeCustom),
    ...Object.keys(afterCustom),
  ]);
  for (const key of [...keys].sort()) {
    const change = createChangedAuditField(
      `custom_data.${key}`,
      beforeCustom[key],
      afterCustom[key],
    );
    if (change) changes.push(change);
  }
  return changes;
}

/**
 * Uses the same presenter as Analytics for audit action titles and fields.
 * Timeline metadata arrives as raw JSON text in `body`, so malformed legacy
 * rows are validated and ignored instead of reaching the client card.
 */
const timelineAuditPresenter = new AuditPresentationService();

function describeAuditRow(row: TimelineRow): { title: string; body: string | null } {
  let metadata: Record<string, unknown> | null = null;
  try {
    const parsed: unknown = row.body ? JSON.parse(row.body) : null;
    if (typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)) {
      metadata = parsed as Record<string, unknown>;
    }
  } catch {
    // Historical metadata is append-only. A malformed row must not break the
    // whole timeline or leak its raw storage representation into the UI.
  }

  const actorName =
    `${row.actor_first_name ?? ""} ${row.actor_last_name ?? ""}`.trim();
  const presented = timelineAuditPresenter.present({
    id: row.id,
    actionKey: row.title,
    actor: {
      id: row.actor_user_id,
      name: actorName || "Системный процесс",
      role: null,
    },
    target: {
      type: row.status ?? "client",
      id: null,
      displayName: null,
    },
    metadata,
    beforeRef: null,
    afterRef: null,
    reason: null,
    reasonText: null,
    occurredAt: row.occurred_at,
  });
  const lines = presented.changes.map((change) => {
    if (change.before === null && change.after === null) {
      return `${change.label}: изменено`;
    }
    return `${change.label}: ${change.before ?? "—"} → ${change.after ?? "—"}`;
  });
  return { title: presented.title, body: lines.length > 0 ? lines.join("\n") : null };
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
