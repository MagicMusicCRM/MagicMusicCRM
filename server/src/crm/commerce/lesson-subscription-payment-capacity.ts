import { UnprocessableEntityException } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { CalculatedLessonClientFact } from "./lesson-settlement-facts.persistence";
import { subscriptionFundingSql } from "./subscription-funding.sql";

export async function assertAutomaticLessonSubscriptionPayment(
  client: PoolClient,
  facts: CalculatedLessonClientFact[],
): Promise<void> {
  const bySubscription = new Map<string, bigint>();
  for (const fact of facts) {
    if (fact.chargeType !== "subscription" || !fact.subscriptionId) continue;
    const [whole, fraction = ""] = fact.calculation.units.split(".");
    const units = BigInt(whole) * 100n + BigInt(fraction.padEnd(2, "0"));
    if (units <= 0n) continue;
    bySubscription.set(fact.subscriptionId, (bySubscription.get(fact.subscriptionId) ?? 0n) + units);
  }
  for (const subscriptionId of [...bySubscription.keys()].sort()) {
    // Serialize against other lessons and subscription payment/refund commands.
    await client.query("select id from app.subscriptions where id=$1 for update", [subscriptionId]);
    const capacity = await client.query<{ covered: boolean }>(
      `select financial.paid_units >=
        coalesce(nullif(issued.commercial_snapshot #>> '{commercialRules,carriedUsedUnits}', '')::numeric, issued.lessons_used, 0)
        + coalesce((select sum(charge.units) from app.lesson_client_charge_facts_effective charge
            where charge.subscription_id=issued.id and charge.charge_type='subscription'), 0)
        + $2::numeric / 100 as covered
       from app.subscriptions issued
       cross join lateral (${subscriptionFundingSql}) financial
       where issued.id=$1`,
      [subscriptionId, bySubscription.get(subscriptionId)!.toString()],
    );
    if (capacity.rows[0]?.covered !== true) {
      throw new UnprocessableEntityException({
        code: "LESSON_SUBSCRIPTION_PAYMENT_REQUIRED", subscriptionId,
      });
    }
  }
}
