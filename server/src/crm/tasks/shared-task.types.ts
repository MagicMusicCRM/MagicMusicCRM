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
  created_at: Date | string;
}

export interface SharedTaskMigrationEvidenceRow {
  legacy_task_id: string;
  shared_task_id: string;
  merge_proof: "exact_common_origin" | "separate_ambiguous";
  source_fingerprint: string;
}
