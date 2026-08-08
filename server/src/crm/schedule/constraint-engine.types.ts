import { PoolClient } from "pg";
import { ClientRefType } from "../dto/client-ref.dto";

export const CONSTRAINT_VIOLATION_CODES = [
  "INVALID_INTERVAL",
  "OUTSIDE_BRANCH_HOURS",
  "TEACHER_UNAVAILABLE",
  "TEACHER_BRANCH_MISMATCH",
  "TEACHER_OVERLAP",
  "CLIENT_OVERLAP",
  "ROOM_OVERLAP",
] as const;

export type ConstraintViolationCode =
  (typeof CONSTRAINT_VIOLATION_CODES)[number];

export type ConstraintResourceType =
  | "interval"
  | "branch"
  | "teacher"
  | "client"
  | "room";

export interface ConstraintResourceRef {
  type: ConstraintResourceType;
  id: string;
}

export interface ConstraintViolation {
  code: ConstraintViolationCode;
  resource: ConstraintResourceRef;
  conflictingLessonIds: string[];
  ruleIds: string[];
}

export interface LessonConstraintDraft {
  clientRef: {
    type: ClientRefType;
    id: string;
  };
  teacherId: string;
  branchId: string;
  roomId: string;
  startAt: string | Date;
  endAt: string | Date;
  excludeLessonId?: string;
}

export interface ConstraintValidationResult {
  valid: boolean;
  violations: ConstraintViolation[];
}

export interface ResolvedConstraintReference {
  teacherBranchAssigned: boolean;
  branchHoursConfigured?: boolean;
  branchWindows: Array<{
    opensAt: string | Date;
    closesAt: string | Date;
  }>;
  teacherRules: Array<{
    id: string;
    available: boolean;
    startsAt: string | Date;
    endsAt: string | Date | null;
  }>;
}

export interface LessonConflict {
  code: Extract<
    ConstraintViolationCode,
    "TEACHER_OVERLAP" | "CLIENT_OVERLAP" | "ROOM_OVERLAP"
  >;
  resource: ConstraintResourceRef;
  lessonId: string;
}

export type ConstraintTransaction = PoolClient;
