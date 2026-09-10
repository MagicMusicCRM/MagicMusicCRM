import { Pool } from "pg";
import { acquireLessonSettlementCoordinationGate } from "../../../crm/commerce/lesson-settlement-locks";
import { lockCoverageSubscription, reconcileSubscriptionCoverage, subscriptionCoversLesson } from "../../../crm/commerce/subscription-coverage.persistence";

// Uses the same allocator as lesson commands. Preview rolls back reservations,
// audit and outbox together. Supply DATABASE_URL explicitly; no production default.
async function main() {
  const args = process.argv.slice(2);
  if (args.some((arg) => arg !== "--apply")) throw new Error("Usage: reconcile-subscription-coverage [--apply]");
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error("DATABASE_URL is required");
  const apply = args.includes("--apply");
  const pool = new Pool({ connectionString, max: 1 });
  const summary = { mode: apply ? "apply" : "preview", subscriptions: 0, changedLessons: 0, reviewRequiredLessons: 0 };
  const changedLessons = new Set<string>(), reviewRequiredLessons = new Set<string>();
  try {
    const subscriptions = await pool.query<{ id: string }>("select id from app.subscriptions where status='active' order by id");
    for (const row of subscriptions.rows) {
      const client = await pool.connect();
      try {
        await client.query("begin");
        await client.query("set local lock_timeout = '10s'");
        await client.query("set local statement_timeout = '60s'");
        await acquireLessonSettlementCoordinationGate(client);
        const subscription = await lockCoverageSubscription(client, row.id);
        if (subscription?.status === "active") {
          const result = await reconcileSubscriptionCoverage(client, subscription,
            (lessonId, studentId) => subscriptionCoversLesson(client, row.id, lessonId, studentId));
          summary.subscriptions++;
          result.changedLessonIds.forEach((id) => changedLessons.add(id));
          result.reviewRequiredLessonIds.forEach((id) => reviewRequiredLessons.add(id));
        }
        await client.query(apply ? "commit" : "rollback");
      } catch (error) {
        await client.query("rollback");
        throw error;
      } finally { client.release(); }
    }
    summary.changedLessons = changedLessons.size;
    summary.reviewRequiredLessons = reviewRequiredLessons.size;
    process.stdout.write(JSON.stringify(summary) + "\n");
  } finally { await pool.end(); }
}

main().catch((error: unknown) => {
  // Neither connection strings nor row payloads belong in operational logs.
  process.stderr.write(`Coverage reconciliation failed: ${error instanceof Error ? error.name : "UnknownError"}\n`);
  process.exitCode = 1;
});
