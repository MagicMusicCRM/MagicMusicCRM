import { UnprocessableEntityException } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { CalculatedLessonClientFact } from "./lesson-settlement-facts.persistence";

/** Automatic completion must not create debt without a staff decision. */
export async function assertAutomaticLessonAccountCapacity(
  client: PoolClient,
  facts: CalculatedLessonClientFact[],
): Promise<void> {
  const byPayer = new Map<string, bigint>();
  for (const fact of facts) {
    if (fact.chargeType !== "personal_account") continue;
    const amount = BigInt(fact.calculation.amountMinor);
    if (amount <= 0n) continue;
    if (!fact.payerStudentId) {
      throw new UnprocessableEntityException({ code: "LESSON_ACCOUNT_PAYER_REQUIRED" });
    }
    byPayer.set(fact.payerStudentId, (byPayer.get(fact.payerStudentId) ?? 0n) + amount);
  }
  const payerIds = [...byPayer.keys()].sort();
  if (!payerIds.length) return;
  // Same student-row lock as account transfers and subscription purchases.
  // NO KEY UPDATE is compatible with earlier payer KEY SHARE reads and avoids
  // a lock-upgrade deadlock between lessons funded by the same account.
  const locked = await client.query<{ id: string }>(
    `select id from app.students where id = any($1::uuid[]) and deleted_at is null
     order by id for no key update`,
    [payerIds],
  );
  if (locked.rows.length !== payerIds.length) {
    throw new UnprocessableEntityException({ code: "LESSON_ACCOUNT_PAYER_REQUIRED" });
  }
  // A separate statement obtains a fresh READ COMMITTED snapshot after waiting.
  const balances = await client.query<{ student_id: string; balance_minor: string }>(
    `select student_id, balance_minor::text from app.commerce_student_account_projection
     where student_id = any($1::uuid[]) and currency_code = 'RUB'`,
    [payerIds],
  );
  const available = new Map(balances.rows.map(row => [row.student_id, BigInt(row.balance_minor)]));
  for (const payerStudentId of payerIds) {
    const balance = available.get(payerStudentId) ?? 0n;
    const requested = byPayer.get(payerStudentId)!;
    if (balance < requested) {
      throw new UnprocessableEntityException({
        code: "LESSON_ACCOUNT_INSUFFICIENT_BALANCE",
        payerStudentId,
        requestedMinor: requested.toString(),
        availableMinor: balance.toString(),
      });
    }
  }
}
