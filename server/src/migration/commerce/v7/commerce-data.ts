import { Pool, PoolClient, QueryResultRow } from "pg";

interface BackfillRow extends QueryResultRow {
  subscriptions_backfilled: string | number;
  payments_backfilled: string | number;
  review_rows: string | number;
}

export interface V7CommerceIssue {
  issueCode: string;
  entityId: string;
  detail: string;
}

export async function backfillV7Commerce(client: PoolClient) {
  const result = await client.query<BackfillRow>(
    "select * from app.backfill_v7_commerce()",
  );
  const row = result.rows[0]!;
  await client.query("select app.repair_v7_legacy_subscription_finance()");
  return {
    subscriptionsBackfilled: Number(row.subscriptions_backfilled),
    paymentsBackfilled: Number(row.payments_backfilled),
    reviewRows: Number(row.review_rows),
  };
}

export async function reconcileV7Commerce(client: PoolClient) {
  const result = await client.query<{
    issue_code: string;
    entity_id: string;
    detail: string;
  }>("select * from app.reconcile_v7_commerce()");
  const subscriptionVersions = await client.query<{
    issue_code: string;
    entity_id: string;
    detail: string;
  }>(`
    select
      'subscription_aggregate_version_mismatch'::text as issue_code,
      subscription.id::text as entity_id,
      concat(
        'subscription=', subscription.version::text,
        ', aggregate=', coalesce(aggregate.version::text, 'missing')
      ) as detail
    from app.subscriptions subscription
    left join app.aggregate_versions aggregate
      on aggregate.aggregate_type = 'commerce:issued-subscription'
     and aggregate.aggregate_id = subscription.id::text
    where subscription.commercial_snapshot is not null
      and aggregate.version is distinct from subscription.version
    order by subscription.id
  `);
  const legacySubscriptionFinance = await client.query<{
    issue_code: string;
    entity_id: string;
    detail: string;
  }>(`
    select
      'subscription_payment_linkage_mismatch'::text as issue_code,
      subscription.id::text as entity_id,
      'legacy subscription, payment and client record are not linked'::text
        as detail
    from app.subscriptions subscription
    left join app.payments payment on payment.id = subscription.payment_id
    left join app.client_payment_records record
      on record.actual_payment_id = payment.id
    where subscription.commercial_snapshot is not null
      and subscription.funding_mode = 'legacy'
      and subscription.payment_id is not null
      and (
        payment.id is null
        or record.id is null
        or payment.issued_subscription_id is distinct from subscription.id
        or record.issued_subscription_id is distinct from subscription.id
        or payment.student_id is distinct from subscription.student_id
        or record.student_id is distinct from subscription.student_id
        or payment.amount_minor is distinct from subscription.final_price_minor
        or record.amount_minor is distinct from subscription.final_price_minor
      )

    union all

    select
      'subscription_obligation_debit_missing'::text as issue_code,
      subscription.id::text as entity_id,
      'legacy subscription has no original debit obligation fact'::text
        as detail
    from app.subscriptions subscription
    where subscription.commercial_snapshot is not null
      and subscription.funding_mode = 'legacy'
      and subscription.payment_id is not null
      and not exists (
        select 1
        from app.subscription_obligation_facts obligation
        where obligation.issued_subscription_id = subscription.id
          and obligation.direction = 'debit'
      )
    order by 1, 2
  `);
  return [
    ...result.rows,
    ...subscriptionVersions.rows,
    ...legacySubscriptionFinance.rows,
  ].map((row) => ({
    issueCode: row.issue_code,
    entityId: row.entity_id,
    detail: row.detail,
  }));
}

async function main() {
  const connectionString =
    process.env.MIGRATION_DATABASE_URL ?? process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error("MIGRATION_DATABASE_URL or DATABASE_URL is required.");
  }
  const pool = new Pool({ connectionString, max: 1 });
  const client = await pool.connect();
  try {
    await client.query("begin");
    const backfill = process.argv.includes("--apply")
      ? await backfillV7Commerce(client)
      : null;
    const issues = await reconcileV7Commerce(client);
    if (backfill) await client.query("commit");
    else await client.query("rollback");
    process.stdout.write(`${JSON.stringify({ backfill, issues })}\n`);
    if (issues.length > 0) process.exitCode = 2;
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

if (require.main === module) {
  main().catch((error: unknown) => {
    process.stderr.write(
      `${error instanceof Error ? error.message : String(error)}\n`,
    );
    process.exitCode = 1;
  });
}
