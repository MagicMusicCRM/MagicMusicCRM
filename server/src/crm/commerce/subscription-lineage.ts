import type { PoolClient } from "pg";

/** Replacement links preserve the issued contract's history and owner. */
export function subscriptionLineageSql(root: string, direction: "ancestors" | "successors") {
  const from = direction === "ancestors" ? "after" : "before";
  const to = direction === "ancestors" ? "before" : "after";
  return `with recursive subscription_lineage(id) as (
    select ${root}::uuid
    union
    select event.${to}_issued_subscription_id
    from app.subscription_lifecycle_events event
    join subscription_lineage chain on chain.id = event.${from}_issued_subscription_id
    join app.subscriptions predecessor on predecessor.id = event.before_issued_subscription_id
    join app.subscriptions successor on successor.id = event.after_issued_subscription_id
    where event.event_type = 'replace' and predecessor.status = 'replaced'
      and predecessor.student_id = successor.student_id
  ) select id from subscription_lineage`;
}

export async function currentSubscriptionId(client: PoolClient, subscriptionId: string): Promise<string> {
  const result = await client.query<{ id: string }>(`
    select issued.id from app.subscriptions issued
    where issued.id in (${subscriptionLineageSql("$1", "successors")})
      and issued.status = 'active'
  `, [subscriptionId]);
  return result.rows.length === 1 ? result.rows[0]!.id : subscriptionId;
}
