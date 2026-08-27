import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import type {
  LessonFinancialDecision,
  LessonSettlementResult,
} from "../commerce/lesson-settlement.port";
import type { LessonSettlementCoverageSnapshot } from "../commerce/subscription-reservation.service";
import type {
  CompleteLessonDraft,
  ExistingLessonDraft,
  LessonDraftInput,
} from "./lesson-draft.contracts";

export type TransitionOperation = "reschedule" | "cancel" | "settle";
export type TransitionState =
  | "scheduled"
  | "settlement_pending"
  | "successfully_completed"
  | "cancelled"
  | "rescheduled";

export type TerminalTransitionState = Exclude<
  TransitionState,
  "scheduled" | "settlement_pending"
>;

export interface GroupParticipantSnapshot {
  studentId: string;
  chargeType: "subscription" | "personal_account" | "none";
  chargeValue: number;
  subscriptionId: string | null;
}

export interface TransitionLessonRow {
  id: string;
  version: number | string;
  lifecycle_state: TransitionState;
  student_id: string | null;
  lead_id: string | null;
  lesson_group_id: string | null;
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  scheduled_at: Date | string;
  duration_minutes: number | string;
  is_trial: boolean;
  notes: string | null;
  snapshot_client_type: "lead" | "student" | null;
  snapshot_client_id: string | null;
  snapshot_group_id: string | null;
  completion_type: string | null;
  client_charge_type: "subscription" | "personal_account" | "none" | null;
  client_charge_value: number | string | null;
  teacher_compensation_type: "fixed" | "hourly" | "none" | null;
  teacher_compensation_value: number | string | null;
  subscription_id: string | null;
  snapshot_trial: boolean | null;
  validation_state: "valid" | "legacy_incomplete" | null;
  participants: GroupParticipantSnapshot[];
}

export interface GroupLessonDraft {
  kind: "group";
  groupId: string;
  teacherId: string;
  branchId: string;
  roomId: string;
  scheduledAt: string;
  durationMinutes: number;
  endAt: string;
  isTrial: boolean;
  notes: string | null;
  completionType: string;
  teacherCompensationType: "fixed" | "hourly" | "none";
  teacherCompensationValue: number;
  participants: GroupParticipantSnapshot[];
}

export type TransitionSuccessor =
  | (CompleteLessonDraft & { kind: "individual" })
  | GroupLessonDraft;

export type TransitionSource = ExistingLessonDraft & {
  lifecycleState: TransitionState;
  groupId: string | null;
  groupSnapshot: {
    completionType: string;
    teacherCompensationType: "fixed" | "hourly" | "none";
    teacherCompensationValue: number;
    trial: boolean;
    validationState: "valid" | "legacy_incomplete";
  } | null;
  participants: GroupParticipantSnapshot[];
};

/** Internal workflow contract. Transport DTO classes are adapters to this shape. */
export interface TransitionPreviewDto {
  expectedVersion: number;
  reasonCode?: string;
  reasonText?: string;
  financialDecision: LessonFinancialDecision;
  successor?: LessonDraftInput;
}

export interface TransitionCommandDto extends TransitionPreviewDto {
  previewToken: string;
  confirm: true;
}

export interface CommittedTransition {
  [key: string]: unknown;
  lessonId: string;
  state: TerminalTransitionState;
  successorId: string | null;
  transitionId: string;
  clientFinancialFactIds: string[];
  teacherFinancialFactId: string;
  financialDecision: LessonFinancialDecision;
  transitionFingerprint: string;
}

export interface CalculatedTransitionPreview extends LessonTransitionPreviewResult {
  transitionFingerprint?: string;
}

export interface BulkTransitionResultRef {
  [key: string]: unknown;
  bulkId: string;
  items: CommittedTransition[];
}

export interface LessonTransitionPreviewResult {
  operation: TransitionOperation;
  source: { id: string; version: number; state: string };
  successor: Record<string, unknown> | null;
  financialDecision: TransitionPreviewDto["financialDecision"];
  violations: unknown[];
  canConfirm: boolean;
  confirmRequired: true;
  financialPreview?: unknown;
  warnings?: string[];
  previewToken?: string;
  previewExpiresAt?: string;
}

export interface LessonTransitionCommandResult {
  source: { id: string; state: TerminalTransitionState; version: number };
  successor: { id: string; state: "scheduled"; version: 1 } | null;
  transitionId: string;
  clientFinancialFactIds: string[];
  teacherFinancialFactId: string;
  financialDecision: LessonFinancialDecision;
  replayed: boolean;
}

export interface LessonBulkTransitionPreviewResult {
  items: Array<LessonTransitionPreviewResult & {
    lessonId: string;
    operation: TransitionOperation;
  }>;
  canConfirm: boolean;
  confirmRequired: true;
  previewToken?: string;
  previewExpiresAt?: string;
}

export interface LessonBulkTransitionCommandResult {
  bulkId: string;
  items: CommittedTransition[];
  replayed: boolean;
}

export type TransitionFinancialProjection = {
  clientFacts: Array<Omit<LessonSettlementResult["clientFacts"][number], "id">>;
  teacherFact: Omit<LessonSettlementResult["teacherFact"], "id">;
};

export interface TransitionFingerprintInput {
  operation: TransitionOperation;
  source: TransitionSource;
  successor: TransitionSuccessor | null;
  dto: TransitionPreviewDto;
  coverage: LessonSettlementCoverageSnapshot;
  financial: TransitionFinancialProjection;
}

export interface BulkFingerprintItem {
  lessonId: string;
  operation: TransitionOperation;
  preview: Pick<CalculatedTransitionPreview, "transitionFingerprint">;
}

export interface CommitTransitionInput {
  actor: ActorContext;
  lessonId: string;
  dto: TransitionPreviewDto;
  operation: TransitionOperation;
  successorId: string | null;
  nextVersion: number;
  expectedFingerprint?: string;
}

export interface TransitionCommitContext {
  client: PoolClient;
  input: CommitTransitionInput;
}

export interface BulkTransitionItem {
  lessonId: string;
  operation: TransitionOperation;
  expectedVersion: number;
  financialDecision: LessonFinancialDecision;
  successor?: LessonDraftInput;
}

export interface BulkTransitionDto {
  reasonCode?: string;
  reasonText: string;
  items: BulkTransitionItem[];
}
