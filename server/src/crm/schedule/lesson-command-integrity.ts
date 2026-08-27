import { UnprocessableEntityException } from "@nestjs/common";
import { createHash } from "node:crypto";
import type { LessonSettlementResult } from "../commerce/lesson-settlement.port";
import type { ExistingLessonDraft } from "./lesson-required-field.validator";
import type { LessonCommandMetadata } from "./lesson-command-metadata";

export interface CurrentLessonRow {
  id: string;
  version: number | string;
  student_id: string | null;
  lead_id: string | null;
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  scheduled_at: Date | string;
  duration_minutes: number | string;
  is_trial: boolean;
  notes: string | null;
  snapshot_client_type: "lead" | "student" | null;
  snapshot_client_id: string | null;
  completion_type: string | null;
  client_charge_type: "subscription" | "personal_account" | "none" | null;
  client_charge_value: number | string | null;
  teacher_compensation_type: "fixed" | "hourly" | "none" | null;
  teacher_compensation_value: number | string | null;
  subscription_id: string | null;
  snapshot_trial: boolean | null;
  validation_state: "valid" | "legacy_incomplete" | null;
}

export function assertLessonCommandMetadata(metadata: LessonCommandMetadata) {
  if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
    throw new UnprocessableEntityException({
      code: "IDEMPOTENCY_KEY_REQUIRED",
      message: "Idempotency-Key must contain 8-160 safe characters.",
    });
  }
  if (!metadata.requestId || metadata.requestId.length > 160) {
    throw new UnprocessableEntityException({
      code: "REQUEST_ID_REQUIRED",
      message: "X-Request-Id is required and must not exceed 160 characters.",
    });
  }
}

export function stableLessonCreateId(
  actorUserId: string,
  idempotencyKey: string,
) {
  const bytes = createHash("sha256")
    .update(`schedule.lesson.create\0${actorUserId}\0${idempotencyKey}`)
    .digest()
    .subarray(0, 16);
  bytes[6] = (bytes[6]! & 0x0f) | 0x50;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join("-");
}

export function toExistingLessonDraft(
  row: CurrentLessonRow,
): ExistingLessonDraft {
  const hasSnapshot =
    row.snapshot_client_type !== null &&
    row.snapshot_client_id !== null &&
    row.completion_type !== null &&
    row.client_charge_type !== null &&
    row.client_charge_value !== null &&
    row.teacher_compensation_type !== null &&
    row.teacher_compensation_value !== null &&
    row.snapshot_trial !== null &&
    row.validation_state !== null;
  const snapshot = hasSnapshot
    ? {
        clientType: row.snapshot_client_type!,
        clientId: row.snapshot_client_id!,
        completionType: row.completion_type!,
        clientChargeType: row.client_charge_type!,
        clientChargeValue: Number(row.client_charge_value),
        teacherCompensationType: row.teacher_compensation_type!,
        teacherCompensationValue: Number(row.teacher_compensation_value),
        subscriptionId: row.subscription_id,
        trial: row.snapshot_trial!,
        validationState: row.validation_state!,
      }
    : null;
  return {
    id: row.id,
    version: Number(row.version),
    studentId: row.student_id,
    leadId: row.lead_id,
    teacherId: row.teacher_id,
    branchId: row.branch_id,
    roomId: row.room_id,
    scheduledAt: row.scheduled_at,
    durationMinutes: Number(row.duration_minutes),
    isTrial: row.is_trial,
    notes: row.notes,
    snapshot,
  };
}

export function lessonFinancialProjection(settled: LessonSettlementResult) {
  return {
    clientFacts: settled.clientFacts.map(({ id: _id, ...fact }) => fact),
    teacherFact: (({ id: _id, ...fact }) => fact)(settled.teacherFact),
  };
}
