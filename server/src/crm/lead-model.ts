import { resolveAge } from "./age";
import { resolveAppealDate } from "./appeal-date";
import { presentableEmail } from "./crm-mappers";
import { StudentRow } from "./student-read";

export interface LeadRow {
  id: string;
  status_id: string | null;
  status_key?: string | null;
  status_name: string | null;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  email: string | null;
  source: string | null;
  source_id?: string | null;
  notes: string | null;
  assigned_to: string | null;
  custom_data: Record<string, unknown> | null;
  created_by: string | null;
  created_at: Date | string;
  updated_at: Date | string;
  blacklisted?: boolean | null;
  blacklist_reason?: string | null;
}

export interface LeadBoardRow extends LeadRow {
  cursor_created_at: string;
  status_color: string | null;
  status_sort_order: number | null;
  assigned_first_name: string | null;
  assigned_last_name: string | null;
  branch_id: string | null;
  branch_name: string | null;
  linked_student_id: string | null;
  linked_user_id: string | null;
  open_tasks_count: string | number;
  comments_count: string | number;
  trial_lessons_count: string | number;
  table_custom_fields?: Record<string, unknown>[] | null;
}

export interface LeadBoardCountRow {
  status_id: string | null;
  count: string | number;
}

export interface LeadBoardColumnDto {
  id: string;
  stageKey: string;
  name: string;
  color: string | null;
  sortOrder: number;
  createdAt: Date | string | null;
  requiresReason: boolean;
  isTerminal: boolean;
  totalCount: number;
  items: Record<string, unknown>[];
  nextCursor: string | null;
}

export interface LeadStatusRow {
  id: string;
  stage_key?: string | null;
  name: string;
  color: string | null;
  sort_order: number;
  created_at: Date | string;
  requires_reason?: boolean;
  is_terminal?: boolean;
}

export interface CommentRow {
  id: string;
  entity_type: string;
  entity_id: string;
  author_id: string | null;
  author_first_name: string | null;
  author_last_name: string | null;
  body: string;
  kind: string;
  created_at: Date | string;
}

export function toNumericStat(
  value: string | number | null | undefined,
): number {
  if (value === null || value === undefined) return 0;
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : 0;
}

export function toLeadDto(row: LeadRow) {
  const appeal = resolveAppealDate(row.custom_data, row.created_at);
  const age = resolveAge(row.custom_data);
  return {
    id: row.id,
    statusId: row.status_id,
    statusKey: row.status_key,
    statusName: row.status_name,
    firstName: row.first_name,
    lastName: row.last_name,
    phone: row.phone,
    email: presentableEmail(row.email),
    source: row.source,
    sourceId: row.source_id ?? null,
    notes: row.notes,
    assignedTo: row.assigned_to,
    customData: row.custom_data ?? {},
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    appealAt: appeal.value,
    appealAtSource: appeal.source,
    age: age.years,
    ageMonths: age.months,
    ageSource: age.source,
    blacklisted: row.blacklisted === true,
    blacklistReason: row.blacklist_reason ?? null,
  };
}

export function toLeadBoardItemDto(row: LeadBoardRow) {
  const assignedName =
    `${row.assigned_first_name ?? ""} ${row.assigned_last_name ?? ""}`.trim();
  return {
    ...toLeadDto(row),
    statusColor: row.status_color,
    statusSortOrder: row.status_sort_order,
    assignedName: assignedName || null,
    branchId: row.branch_id,
    branchName: row.branch_name,
    linkedStudentId: row.linked_student_id,
    linkedUserId: row.linked_user_id,
    openTasksCount: toNumericStat(row.open_tasks_count),
    commentsCount: toNumericStat(row.comments_count),
    trialLessonsCount: toNumericStat(row.trial_lessons_count),
    tableFields: row.table_custom_fields ?? [],
  };
}

export function toLeadStatusDto(row: LeadStatusRow) {
  return {
    id: row.id,
    stageKey: row.stage_key ?? row.id,
    name: row.name,
    color: row.color,
    sortOrder: row.sort_order,
    createdAt: row.created_at,
    requiresReason: row.requires_reason ?? false,
    isTerminal: row.is_terminal ?? false,
  };
}

export function toCommentDto(row: CommentRow) {
  const authorName =
    `${row.author_first_name ?? ""} ${row.author_last_name ?? ""}`.trim();
  return {
    id: row.id,
    entityType: row.entity_type,
    entityId: row.entity_id,
    authorId: row.author_id,
    authorName: authorName || null,
    body: row.body,
    kind: row.kind,
    progress: row.kind === "progress",
    createdAt: row.created_at,
  };
}

export function toStudentDto(row: StudentRow) {
  return {
    id: row.id,
    leadId: row.lead_id,
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
  };
}

export function encodeLeadCursor(
  row: Pick<LeadBoardRow, "cursor_created_at" | "id">,
) {
  return `${row.cursor_created_at}|${row.id}`;
}
