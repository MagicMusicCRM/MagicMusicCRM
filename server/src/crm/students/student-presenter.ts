import { resolveAge } from "../age";
import { resolveAppealDate } from "../appeal-date";
import { presentableEmail } from "../crm-mappers";
import { StudentRow } from "../student-read";

export interface StudentSearchRow extends StudentRow {
  total_count: string | number;
  branch_id: string | null;
  branch_name: string | null;
  groups_count: string | number;
  open_tasks_count: string | number;
  lessons_count: string | number;
  payments_total: string | number | null;
  linked_user_id: string | null;
  linked_user_email: string | null;
  is_app_account: boolean | null;
  disciplines: { id: string; name: string }[] | null;
  table_custom_fields: Record<string, unknown>[] | null;
}

export interface StudentGroupRow {
  id: string;
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  name: string;
  price_per_lesson: string | null;
  // null = use the teacher rate; 0 = included in salary.
  teacher_rate?: string | number | null;
  teacher_name: string | null;
  branch_name: string | null;
  room_name: string | null;
  created_at: Date | string;
}

export function toStudentDto(row: StudentRow) {
  const appeal = resolveAppealDate(row.custom_data, row.created_at);
  const age = resolveAge(row.custom_data);
  return {
    id: row.id,
    version: Number(row.version ?? 1),
    leadId: row.lead_id,
    sourceId: row.source_id ?? null,
    sourceName: row.source_name ?? null,
    status: row.status,
    customData: row.custom_data ?? {},
    profileId: row.profile_id,
    profileUserId: row.profile_user_id,
    firstName: row.first_name,
    lastName: row.last_name,
    email: presentableEmail(row.email),
    phone: row.phone,
    teacherUserIds: row.teacher_user_ids ?? [],
    createdAt: row.created_at,
    appealAt: appeal.value,
    appealAtSource: appeal.source,
    age: age.years,
    ageMonths: age.months,
    ageSource: age.source,
    blacklisted: row.blacklisted === true,
    blacklistReason: row.blacklist_reason ?? null,
  };
}

export function toStudentSearchDto(row: StudentSearchRow) {
  return {
    ...toStudentDto(row),
    branchId: row.branch_id,
    branchName: row.branch_name,
    groupsCount: toNumericStat(row.groups_count),
    openTasksCount: toNumericStat(row.open_tasks_count),
    lessonsCount: toNumericStat(row.lessons_count),
    paymentsTotal: toNumericStat(row.payments_total),
    linkedUserId: row.linked_user_id,
    linkedUserEmail: row.linked_user_email,
    isAppAccount: row.is_app_account ?? false,
    disciplines: row.disciplines ?? [],
    tableFields: row.table_custom_fields ?? [],
  };
}

export function toStudentGroupDto(row: StudentGroupRow) {
  return {
    id: row.id,
    teacherId: row.teacher_id,
    branchId: row.branch_id,
    roomId: row.room_id,
    name: row.name,
    pricePerLesson:
      row.price_per_lesson === null ? null : Number(row.price_per_lesson),
    teacherRate:
      row.teacher_rate === null || row.teacher_rate === undefined
        ? null
        : Number(row.teacher_rate),
    teacherName: row.teacher_name || null,
    branchName: row.branch_name,
    roomName: row.room_name,
    createdAt: row.created_at,
  };
}

export function toNumericStat(value: string | number | null | undefined): number {
  if (value === null || value === undefined) return 0;
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : 0;
}
