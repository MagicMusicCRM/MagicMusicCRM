import { NotFoundException } from "@nestjs/common";
import type { PoolClient } from "pg";
import { branchIdExpr, currentActorRoleSql, managerBranchScopeSql } from "../branch-scope";
import { normalizeCommercialPrice } from "./commercial-price";
import { invalidLessonSettlementDecision } from "./lesson-settlement-catalog";
import { rublesToMinor } from "./lesson-settlement.calculation";
import type { LessonFinancialDecision, LessonPriceSnapshot } from "./lesson-settlement.port";
import type { LessonSettlementChargeSource } from "./lesson-settlement-facts.persistence";

type ClientDecision = NonNullable<LessonFinancialDecision["clientDecisions"]>[number];

/** One funding interpretation for reservation planning, settlement and replay. */
export function resolveLessonFunding(
  charge: LessonSettlementChargeSource,
  selected?: ClientDecision,
) {
  const inheritedSubscription = selected?.subscriptionId ?? charge.subscription_id;
  const chargeType = selected?.chargeType ?? (inheritedSubscription ? "subscription" : charge.charge_type);
  const subscriptionId = chargeType === "subscription" ? inheritedSubscription : null;
  if (chargeType === "subscription" && !subscriptionId) {
    invalidLessonSettlementDecision("PAYER_SUBSCRIPTION_REQUIRED", "clientDecisions.subscriptionId");
  }
  if (selected?.payerStudentId && chargeType === "none") {
    invalidLessonSettlementDecision("PAYER_FUNDING_SOURCE_REQUIRED", "clientDecisions.payerStudentId");
  }
  const hasPricing = selected?.basePriceMinor !== undefined ||
    selected?.discount !== undefined || selected?.surcharge !== undefined;
  if (chargeType !== "personal_account" && hasPricing) {
    invalidLessonSettlementDecision("LESSON_PRICE_REQUIRES_PERSONAL_ACCOUNT", "clientDecisions.basePriceMinor");
  }
  let pricingSnapshot: LessonPriceSnapshot | null = null;
  let baseChargeMinor = 0n;
  if (chargeType === "personal_account") {
    if (selected?.chargeType === "personal_account" &&
        charge.client_type === "lead" && !selected.payerStudentId) {
      invalidLessonSettlementDecision("PAYER_STUDENT_REQUIRED", "clientDecisions.payerStudentId");
    }
    if (selected?.chargeType === "personal_account" && selected.basePriceMinor == null) {
      invalidLessonSettlementDecision("LESSON_BASE_PRICE_REQUIRED", "clientDecisions.basePriceMinor");
    }
    const basePriceMinor = selected?.basePriceMinor ?? rublesToMinor(charge.charge_value).toString();
    if (!/^(0|[1-9]\d{0,11})$/.test(basePriceMinor)) {
      invalidLessonSettlementDecision("LESSON_BASE_PRICE_INVALID", "clientDecisions.basePriceMinor");
    }
    const pricing = normalizeCommercialPrice(basePriceMinor, selected ?? {});
    if (BigInt(pricing.finalPriceMinor) > 999_999_999_999n) {
      invalidLessonSettlementDecision("LESSON_PRICE_OUT_OF_RANGE", "clientDecisions.basePriceMinor");
    }
    baseChargeMinor = BigInt(pricing.finalPriceMinor);
    pricingSnapshot = {
      basePriceMinor,
      discount: pricing.discount.snapshot,
      surcharge: pricing.surcharge.snapshot,
      finalPriceMinor: pricing.finalPriceMinor,
    };
  }
  return {
    chargeType,
    subscriptionId,
    baseChargeMinor,
    pricingSnapshot,
    payerStudentId: chargeType === "none" ? null : selected?.payerStudentId ??
      (charge.client_type === "student" ? charge.client_id : null),
  };
}

/** Explicit payers are authorized using current database role and resource scope. */
export async function assertLessonPayers(
  client: PoolClient,
  decision: LessonFinancialDecision,
  actorUserId?: string,
): Promise<void> {
  const payerIds = [...new Set((decision.clientDecisions ?? []).flatMap(
    (item) => item.payerStudentId ? [item.payerStudentId] : [],
  ))].sort();
  if (!payerIds.length) return;
  const scope = actorUserId ? `and ${managerBranchScopeSql({
    roleExpression: currentActorRoleSql("$2"),
    userIdExpression: "$2",
    branchExpression: branchIdExpr("student"),
  })}` : "";
  const result = await client.query<{ id: string }>(
    `select student.id from app.students student
     where student.id = any($1::uuid[]) and student.deleted_at is null
       ${scope} order by student.id for key share`,
    actorUserId ? [payerIds, actorUserId] : [payerIds],
  );
  if (result.rows.length !== payerIds.length) throw new NotFoundException("Плательщик недоступен.");
}
