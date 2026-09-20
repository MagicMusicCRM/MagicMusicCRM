import { ConflictException, UnprocessableEntityException } from "@nestjs/common";
import type {
  TransitionOperation,
  TransitionSource,
} from "./lesson-transition.types";

export const isCompletedReschedule = (
  source: TransitionSource,
  operation: TransitionOperation,
) => operation === "reschedule" &&
  source.lifecycleState === "successfully_completed";

export function assertTransitionSourceAllowed(
  source: TransitionSource,
  operation: TransitionOperation,
): void {
  const settleAllowed = operation === "settle" &&
    source.lifecycleState === "settlement_pending";
  const ordinaryAllowed = operation !== "settle" &&
    ["scheduled", "settlement_pending"].includes(source.lifecycleState);
  if (settleAllowed || ordinaryAllowed || isCompletedReschedule(source, operation)) {
    return;
  }
  throw new ConflictException({
    code: operation === "settle"
      ? "LESSON_SETTLEMENT_REVIEW_NOT_REQUIRED"
      : "LESSON_ALREADY_TERMINAL",
    state: source.lifecycleState,
  });
}

export function assertCompleteTransitionSource(source: TransitionSource): void {
  const individualValid = source.snapshot?.validationState === "valid" &&
    !source.groupId;
  const groupValid = source.groupSnapshot?.validationState === "valid" &&
    Boolean(source.groupId) && source.participants.length > 0;
  if (individualValid || groupValid) return;
  throw new UnprocessableEntityException({
    code: "LESSON_SNAPSHOT_INCOMPLETE",
    fields: ["snapshot"],
  });
}
