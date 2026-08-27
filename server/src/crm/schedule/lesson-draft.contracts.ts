export type LessonClientRefType = "lead" | "student";

export interface LessonDraftInput {
  studentId?: string;
  leadId?: string;
  groupId?: string;
  teacherId?: string;
  branchId?: string;
  roomId?: string;
  scheduledAt?: string;
  durationMinutes?: number;
  status?: string;
  isTrial?: boolean;
  completionType?: string;
  clientChargeType?: "subscription" | "personal_account" | "none";
  clientChargeValue?: number;
  teacherCompensationType?: "fixed" | "hourly" | "none";
  teacherCompensationValue?: number;
  subscriptionId?: string;
  force?: boolean;
  clientRef?: { type: LessonClientRefType; id: string };
  notes?: string;
  teacherRate?: number;
}

export interface ExistingLessonDraft {
  id: string;
  version: number;
  studentId: string | null;
  leadId: string | null;
  teacherId: string | null;
  branchId: string | null;
  roomId: string | null;
  scheduledAt: string | Date;
  durationMinutes: number;
  isTrial: boolean;
  notes: string | null;
  snapshot: {
    clientType: LessonClientRefType;
    clientId: string;
    completionType: string;
    clientChargeType: "subscription" | "personal_account" | "none";
    clientChargeValue: number;
    teacherCompensationType: "fixed" | "hourly" | "none";
    teacherCompensationValue: number;
    subscriptionId: string | null;
    trial: boolean;
    validationState: "valid" | "legacy_incomplete";
  } | null;
}

export interface CompleteLessonDraft {
  clientRef: { type: LessonClientRefType; id: string };
  teacherId: string;
  branchId: string;
  roomId: string;
  scheduledAt: string;
  durationMinutes: number;
  endAt: string;
  isTrial: boolean;
  notes: string | null;
  completionType: string;
  clientChargeType: "subscription" | "personal_account" | "none";
  clientChargeValue: number;
  teacherCompensationType: "fixed" | "hourly" | "none";
  teacherCompensationValue: number;
  subscriptionId: string | null;
}
