export type SchedulePlanKind = "individual" | "group";
export type SchedulePlanStatus = "active" | "ended";

export interface SchedulePlanEntity {
  id: string;
  kind: SchedulePlanKind;
  title: string;
  studentId: string | null;
  groupId: string | null;
  subscriptionId: string | null;
  activeFrom: string;
  activeUntil: string | null;
  status: SchedulePlanStatus;
  version: number;
  endedAt: Date | null;
  endedBy: string | null;
  endReason: string | null;
}

export interface SchedulePlanParticipantEntity {
  id: string;
  planId: string;
  studentId: string;
  subscriptionId: string;
  effectiveFrom: string;
  effectiveUntil: string | null;
  version: number;
}
