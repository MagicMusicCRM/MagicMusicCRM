import { ActorContext } from "../../common/security/actor-context";

export type TeacherStatsUnitType =
  "group" | "individual" | "group_trial" | "individual_trial";

export interface PayrollMutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

export interface PayrollLessonFilters {
  actor: ActorContext;
  teacherId?: string | null;
  branchId?: string | null;
  from?: string | null;
  to?: string | null;
}

export interface PayrollLessonRow {
  id: string;
  rate_mutation_version?: string | number;
  teacher_id: string;
  student_id: string | null;
  lead_id: string | null;
  group_id: string | null;
  group_name: string | null;
  student_name: string | null;
  lead_name: string | null;
  scheduled_at: Date | string;
  duration_minutes: number | string;
  is_trial: boolean;
  group_rate: string | number | null;
  teacher_rate: string | number | null;
  attendance_kind: string | null;
  charge_share: string | number | null;
  settlement_fact_id: string | null;
  settled_amount_minor: string | number | null;
  compensation_type?: string | null;
  compensation_rule_key?: string | null;
  compensation_rule_label?: string | null;
  compensation_actual_value?: string | number | null;
  teacher_snapshot_rate?: string | number | null;
  compensation_override_reason?: string | null;
}

export interface PayrollLessonAccrual {
  hours: number;
  scheduledHours: number;
  creditedHours: number;
  rate: number;
  coefficient: number;
  amount: number;
}

export interface TeacherRateRow {
  id?: string;
  teacher_id: string;
  rate: string | number;
  effective_from: Date | string;
  created_at?: Date | string;
  author_first_name?: string | null;
  author_last_name?: string | null;
}

export interface TeacherRateEntry {
  id: string | null;
  rate: number;
  effectiveFrom: string;
  createdAt: Date | string | null;
  authorName: string | null;
}

export interface TeacherPayoutRow {
  id: string;
  teacher_id: string;
  amount: string | number;
  kind: string;
  comment: string | null;
  paid_at: Date | string;
  author_first_name?: string | null;
  author_last_name?: string | null;
}

export interface TeacherPayrollHeader {
  id: string;
  version: string | number;
}

export interface TeacherMovementTotals {
  paid: number;
  bonus: number;
  deduction: number;
}

export interface TeacherReportReadInput {
  teacherId: string | null;
  lessonTeacherIds: string[];
  status: string | null;
  discipline: string | null;
  category: string | null;
}

export interface TeacherReportRow {
  id: string;
  name: string;
  salary: string | number | null;
}
