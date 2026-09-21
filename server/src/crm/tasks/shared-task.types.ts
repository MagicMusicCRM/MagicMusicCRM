export type SharedTaskState = "open" | "closed";
export type SharedTaskAudienceType = "user" | "branch" | "allBranches";
export type SharedTaskResolutionAction = "list" | "close" | "reminder";

export interface SharedTaskRow {
  id: string;
  title: string;
  body: string | null;
  all_day: boolean;
  start_at: Date | string | null;
  end_at: Date | string | null;
  state: SharedTaskState;
  priority: "low" | "medium" | "high";
  branch_id: string | null;
  linked_entity_type: string | null;
  linked_entity_id: string | null;
  version: number | string;
  created_by: string | null;
  origin: "runtime" | "legacy_backfill";
  migration_state: "runtime" | "exact_merged" | "separate";
  created_at: Date | string;
  updated_at: Date | string;
}

export interface TaskAudienceRow {
  id: string;
  task_id: string;
  audience_type: SharedTaskAudienceType;
  target_id: string | null;
  created_at: Date | string;
}

export interface TaskCloseRow {
  id: string;
  task_id: string;
  closed_at: Date | string;
  closed_by: string;
  request_id: string;
  result_code: string | null;
  result_label: string | null;
  comment: string | null;
  planned_start_at: Date | string | null;
  planned_all_day: boolean | null;
  was_overdue: boolean | null;
  created_at: Date | string;
}

export interface SharedTaskResultRow {
  task_id: string;
  title: string;
  body: string | null;
  linked_entity_type: string | null;
  linked_entity_id: string | null;
  linked_entity_label: string | null;
  audiences: Array<{
    type: SharedTaskAudienceType;
    targetId?: string;
    label: string;
    entityType?: "staff" | "teacher";
    entityId?: string;
  }>;
  close_id: string | null;
  closed_at: Date | string | null;
  closed_by: string | null;
  closed_by_name: string | null;
  closed_by_entity_type: "staff" | "teacher" | null;
  closed_by_entity_id: string | null;
  result_code: string | null;
  result_label: string | null;
  comment: string | null;
  planned_start_at: Date | string | null;
  planned_all_day: boolean | null;
  was_overdue: boolean | null;
  total_count: number | string;
  overdue_count: number | string;
  missing_result_count: number | string;
}

export interface SharedTaskMigrationEvidenceRow {
  legacy_task_id: string;
  shared_task_id: string;
  merge_proof: "exact_common_origin" | "separate_ambiguous";
  source_fingerprint: string;
}

export interface SharedTaskReminderRow {
  id: string;
  task_id: string;
  due_at: Date | string;
  channel: "in_app" | "push" | "email";
  status: "pending" | "claimed" | "delivered" | "cancelled" | "poison";
  dedupe_key: string;
  attempts: number | string;
  next_attempt_at: Date | string | null;
  claimed_at: Date | string | null;
  claimed_by: string | null;
  delivered_at: Date | string | null;
  last_error: string | null;
}

export interface ResolvedSharedTaskRow extends SharedTaskRow {
  matched_audience_id: string;
  matched_audience_type: SharedTaskAudienceType;
  matched_target_id: string | null;
  membership_version: string;
  close_id: string | null;
  closed_at: Date | string | null;
  closed_by: string | null;
  close_request_id: string | null;
  close_result_code: string | null;
  close_result_label: string | null;
  close_comment: string | null;
  close_planned_start_at: Date | string | null;
  close_planned_all_day: boolean | null;
  close_was_overdue: boolean | null;
}
