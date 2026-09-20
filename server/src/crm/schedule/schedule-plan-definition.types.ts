import type {
  SchedulePlanParticipantDto,
  SchedulePlanRowDto,
} from "../dto/schedule-plan.dto";
import type { SchedulePlanUpdateMode } from "./schedule-plan-backdate";
import type {
  LockedSchedulePlan,
  SchedulePlanSeriesSnapshot,
} from "./schedule-plan.repository";

export interface NormalizedSchedulePlanCreate {
  kind: "individual" | "group";
  title: string;
  studentId: string | null;
  groupId: string | null;
  subscriptionId: string | null;
  activeFrom: string;
  activeUntil: string | null;
  participants: SchedulePlanParticipantDto[];
  rows: SchedulePlanRowDto[];
}

export interface PreparedSchedulePlanUpdate {
  plan: LockedSchedulePlan;
  mode: SchedulePlanUpdateMode;
  participants: SchedulePlanParticipantDto[];
  subscriptionId: string | null;
  activeUntil: string | null;
  studentIds: string[];
  activeSeries: SchedulePlanSeriesSnapshot[];
  effectiveFrom: string;
  prefixUntil: string | null;
}

export interface SchedulePlanValidationInput {
  planId: string;
  kind: "individual" | "group";
  studentId: string | null;
  groupId: string | null;
  subscriptionId: string | null;
  participants: SchedulePlanParticipantDto[];
  rows: SchedulePlanRowDto[];
}

export interface NormalizedSchedulePlanEnd {
  expectedVersion: number;
  lastDate: string;
  reasonText: string;
}
