import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import type {
  LessonFinancialDecision,
  LessonSettlementInput,
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
  excluded_participant_ids: string[];
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
  excludedParticipantIds: string[];
};

interface TransitionInputBase {
  expectedVersion: number;
  reasonCode?: string;
  reasonText?: string;
}

export type FinancialTransitionPreviewDto = TransitionInputBase & {
  operation: "cancel" | "settle";
  financialDecision: LessonFinancialDecision;
  sourceFinancialDecision?: never;
  successorFinancialDecision?: never;
  successor?: never;
};

export type NormalizedReschedulePreview = TransitionInputBase & {
  operation: "reschedule";
  successor: LessonDraftInput;
  financialDecision?: never;
  sourceFinancialDecision: LessonFinancialDecision;
  successorFinancialDecision: LessonFinancialDecision;
};

/** Internal workflow contract. Transport DTO classes are adapters to this union. */
export type TransitionPreviewDto =
  | FinancialTransitionPreviewDto
  | NormalizedReschedulePreview;

export interface PreparedRescheduleFinancials {
  sourceFinancialDecision: LessonFinancialDecision & {
    teacherCompensationSource: "automatic" | "manual";
  };
  successorFinancialDecision: LessonFinancialDecision & {
    teacherCompensationSource: "automatic" | "manual";
  };
}

type ResolvedDecision = LessonFinancialDecision & {
  teacherCompensationSource: "automatic" | "manual";
};

type ConfigurationRevisionIds = NonNullable<
  LessonSettlementInput["configurationRevisionIds"]
>;

export type ResolvedFinancialTransitionDto = Omit<
  FinancialTransitionPreviewDto,
  "financialDecision"
> & {
  financialDecision: ResolvedDecision;
  configurationRevisionIds: NonNullable<
    LessonSettlementInput["configurationRevisionIds"]
  >;
};

export type ResolvedRescheduleTransitionDto = Omit<
  NormalizedReschedulePreview,
  "sourceFinancialDecision" | "successorFinancialDecision"
> & PreparedRescheduleFinancials & {
  sourceConfigurationRevisionIds: ConfigurationRevisionIds;
  successorConfigurationRevisionIds: ConfigurationRevisionIds;
};

export type ResolvedTransitionDto =
  | ResolvedFinancialTransitionDto
  | ResolvedRescheduleTransitionDto;

type ConfirmedTransition<T> = T extends unknown ? T & {
  previewToken: string;
  confirm: true;
} : never;

export type TransitionCommandDto = ConfirmedTransition<TransitionPreviewDto>;

interface CommittedTransitionBase {
  [key: string]: unknown;
  lessonId: string;
  transitionId: string;
  clientFinancialFactIds: string[];
  teacherFinancialFactId: string;
  transitionFingerprint: string;
}

export type CommittedTransition =
  | (CommittedTransitionBase & {
      state: "rescheduled";
      successorId: string;
      /** Build 210 response alias with successor semantics. */
      financialDecision: LessonFinancialDecision;
      sourceFinancialDecision: LessonFinancialDecision;
      successorFinancialDecision: LessonFinancialDecision;
    })
  | (CommittedTransitionBase & {
      state: "cancelled" | "successfully_completed";
      successorId: null;
      financialDecision: LessonFinancialDecision;
      sourceFinancialDecision?: never;
      successorFinancialDecision?: never;
    });

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
  financialDecision?: LessonFinancialDecision;
  sourceFinancialDecision?: LessonFinancialDecision;
  successorFinancialDecision?: LessonFinancialDecision;
  violations: unknown[];
  canConfirm: boolean;
  confirmRequired: true;
  financialPreview?: unknown;
  sourceFinancialPreview?: TransitionFinancialProjection;
  successorPlannedSettlementPreview?: PlannedSettlementProjection;
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
  sourceFinancialDecision?: LessonFinancialDecision;
  successorFinancialDecision?: LessonFinancialDecision;
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

export interface PlannedSettlementProjection {
  financialDecision: LessonFinancialDecision;
  settlementTypeLabel: string;
  teacherCompensationLabel: string;
}

export interface TransitionFingerprintInput {
  operation: TransitionOperation;
  source: TransitionSource;
  successor: TransitionSuccessor | null;
  dto: TransitionPreviewDto;
  coverage: LessonSettlementCoverageSnapshot;
  financial: TransitionFinancialProjection;
  successorPlannedSettlement?: PlannedSettlementProjection;
}

export interface BulkFingerprintItem {
  lessonId: string;
  operation: TransitionOperation;
  preview: Pick<CalculatedTransitionPreview, "transitionFingerprint">;
}

interface CommitTransitionInputBase {
  actor: ActorContext;
  lessonId: string;
  nextVersion: number;
  expectedFingerprint?: string;
}

export type CommitTransitionInput =
  | (CommitTransitionInputBase & {
      dto: NormalizedReschedulePreview;
      operation: "reschedule";
      successorId: string;
    })
  | (CommitTransitionInputBase & {
      dto: FinancialTransitionPreviewDto;
      operation: "cancel" | "settle";
      successorId: null;
    });

export interface TransitionCommitContext {
  client: PoolClient;
  input: CommitTransitionInput;
}

interface BulkTransitionItemBase {
  lessonId: string;
  expectedVersion: number;
}

export type BulkTransitionItem =
  | (BulkTransitionItemBase & {
      operation: "cancel" | "settle";
      financialDecision: LessonFinancialDecision;
      successor?: never;
      sourceFinancialDecision?: never;
      successorFinancialDecision?: never;
    })
  | (BulkTransitionItemBase & {
      operation: "reschedule";
      financialDecision?: never;
      successor: LessonDraftInput;
      sourceFinancialDecision: LessonFinancialDecision;
      successorFinancialDecision: LessonFinancialDecision;
    });

export type BulkTransitionInputItem =
  | (BulkTransitionItemBase & {
      operation: "cancel" | "settle";
      financialDecision: LessonFinancialDecision;
      successor?: never;
      successorFinancialDecision?: never;
      sourceFinancialDecision?: never;
    })
  | (BulkTransitionItemBase & {
      operation: "reschedule";
      successor: LessonDraftInput;
      /** Build 210 request alias; normalized as successor-only. */
      financialDecision?: LessonFinancialDecision;
      successorFinancialDecision?: LessonFinancialDecision;
      sourceFinancialDecision?: never;
    });

export interface BulkTransitionDto {
  reasonCode?: string;
  reasonText: string;
  items: BulkTransitionInputItem[];
}
