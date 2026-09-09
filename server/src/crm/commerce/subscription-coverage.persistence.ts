import { randomUUID } from "node:crypto";
import { UnprocessableEntityException } from "@nestjs/common";
import type { PoolClient } from "pg";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { loadLessonSettlementPlan, plannedLessonSubscriptionAllocations } from "./lesson-settlement-plan.persistence";
import type { PlannedSubscriptionAllocation } from "./lesson-settlement.port";

export interface CoverageSubscription {
  id: string;
  student_id: string;
  status: string;
  lessons_total: string;
  lessons_used: string;
}

export interface CoverageOverride extends PlannedSubscriptionAllocation {
  lessonId: string;
}

export interface CoverageReconciliationResult {
  coveredLessonIds: Set<string>;
  changedLessonIds: string[];
  reviewRequiredLessonIds: string[];
}

export async function lockCoverageSubscription(client: PoolClient, subscriptionId: string): Promise<CoverageSubscription | null> {
  const result = await client.query<CoverageSubscription>(`
    select id, student_id, status, lessons_total, lessons_used
    from app.subscriptions where id = $1 for update
  `, [subscriptionId]);
  return result.rows[0] ?? null;
}

export async function subscriptionCoversLesson(client: PoolClient, subscriptionId: string, lessonId: string, studentId: string): Promise<boolean> {
  const result = await client.query<{ covered: boolean }>(`
    select exists (
      select 1 from app.subscriptions subscription
      join app.lessons lesson on lesson.id = $2
      join app.students owner on owner.id = subscription.student_id and owner.deleted_at is null
      join app.students recipient on recipient.id = $3 and recipient.deleted_at is null
      left join app.schedule_series series on series.id = lesson.series_id
      left join app.branches branch on branch.id = lesson.branch_id
      left join app.subscription_packages package on package.id = subscription.package_id
      where subscription.id = $1 and owner.branch_id = lesson.branch_id
        and recipient.branch_id = lesson.branch_id
        and (package.branch_id is null or package.branch_id = lesson.branch_id)
        and (subscription.starts_at is null or subscription.starts_at <=
          timezone(coalesce(series.timezone_name, branch.timezone_name, 'Europe/Moscow'), lesson.scheduled_at)::date)
        and (subscription.expires_at is null or subscription.expires_at >=
          timezone(coalesce(series.timezone_name, branch.timezone_name, 'Europe/Moscow'), lesson.scheduled_at)::date)
    ) as covered
  `, [subscriptionId, lessonId, studentId]);
  return result.rows[0]?.covered === true;
}

export async function synchronizeSubscriptionCoverage(client: PoolClient, subscriptionIds: string[], excludedLessonIds: string[] = []): Promise<void> {
  for (const id of [...new Set(subscriptionIds)].sort()) {
    const subscription = await lockCoverageSubscription(client, id);
    if (subscription) await reconcileSubscriptionCoverage(client, subscription,
      (lessonId, studentId) => subscriptionCoversLesson(client, id, lessonId, studentId), { excludedLessonIds });
  }
}

export async function releaseLessonCoverage(client: PoolClient, lessonIds: string[]): Promise<number> {
  if (!lessonIds.length) return 0;
  const subscriptions = await client.query<{ subscription_id: string }>(`
    select distinct subscription_id from app.lesson_reservations
    where lesson_id = any($1::uuid[]) and state = 'reserved' order by subscription_id
  `, [lessonIds]);
  for (const row of subscriptions.rows) await lockCoverageSubscription(client, row.subscription_id);
  const result = await client.query(`
    update app.lesson_reservations set state = 'released', financial_fact_id = null
    where lesson_id = any($1::uuid[]) and state = 'reserved'
  `, [lessonIds]);
  await synchronizeSubscriptionCoverage(client, subscriptions.rows.map((row) => row.subscription_id), lessonIds);
  return result.rowCount ?? 0;
}

// The caller holds the subscription row lock. Never lock another lesson here:
// terminal commands lock their lesson before its subscription. Coverage has its
// own versioned, append-only reservation history and signed preview fingerprint.
export async function reconcileSubscriptionCoverage(
  client: PoolClient,
  subscription: CoverageSubscription,
  coversLesson: (lessonId: string, studentId: string) => Promise<boolean>,
  options: { override?: CoverageOverride; excludedLessonIds?: string[] } = {},
): Promise<CoverageReconciliationResult> {
  const excluded = options.excludedLessonIds ?? [];
  const rows = await client.query<{
    id: string; scheduled_at: Date; reservation_id: string | null;
    reserved_units: string | null; movable: boolean;
  }>(`
    select lesson.id, lesson.scheduled_at, reservation.id as reservation_id,
      reservation.units::text as reserved_units,
      (lesson.deleted_at is null and (lesson.id = $3::uuid or
        (lesson.lifecycle_state = 'scheduled' and funding_plan.state = 'planned'))) as movable
    from app.lessons lesson
    left join app.lesson_settlement_plans funding_plan on funding_plan.lesson_id = lesson.id
    left join app.lesson_reservations reservation
      on reservation.lesson_id = lesson.id and reservation.subscription_id = $1
      and reservation.state = 'reserved'
    where not (lesson.id = any($2::uuid[])) and (
      reservation.id is not null or lesson.id = $3::uuid or (
        lesson.deleted_at is null and lesson.lifecycle_state = 'scheduled'
        and not exists (select 1 from app.lesson_reservations consumed
          where consumed.lesson_id = lesson.id and consumed.subscription_id = $1
            and consumed.state = 'consumed')
        and (
          exists (select 1 from app.lesson_snapshots snapshot
            where snapshot.lesson_id = lesson.id and snapshot.subscription_id = $1)
          or exists (select 1 from app.lesson_snapshot_participants participant
            where participant.lesson_id = lesson.id and participant.subscription_id = $1)
          or exists (select 1 from app.lesson_settlement_plans plan,
              jsonb_array_elements(coalesce(plan.decision->'clientDecisions', '[]'::jsonb)) choice
            where plan.lesson_id = lesson.id and choice->>'subscriptionId' = $1::text)
        )
      ))
    order by lesson.scheduled_at, lesson.id
  `, [subscription.id, excluded, options.override?.lessonId ?? null]);
  const used = await client.query<{ units: string }>(`
    select ($2::numeric + coalesce(sum(units), 0))::text as units
    from app.lesson_client_charge_facts_effective
    where subscription_id = $1 and charge_type = 'subscription'
  `, [subscription.id, subscription.lessons_used]);
  // Reservation units are numeric(12,2); integer hundredths avoid cumulative
  // rounding drift for shortened lessons.
  const hundredths = (units: string | number) => Math.round(Number(units) * 100);
  const candidates = new Map<string, number>();
  const reviewRequiredLessonIds: string[] = [];
  for (const row of rows.rows) {
    if (!row.movable || subscription.status !== "active") continue;
    let allocations: PlannedSubscriptionAllocation[];
    if (options.override?.lessonId === row.id) {
      allocations = [options.override];
    } else {
      const plan = await loadLessonSettlementPlan(client, row.id);
      if (!plan || plan.state !== "planned") continue;
      try {
        allocations = await plannedLessonSubscriptionAllocations(client, row.id, plan);
      } catch (error) {
        if (!(error instanceof UnprocessableEntityException)) throw error;
        // An inconsistent historical plan must be corrected through its own
        // signed editor. Preserve its reserve; do not prevent unrelated work.
        row.movable = false;
        reviewRequiredLessonIds.push(row.id);
        continue;
      }
    }
    const matching = allocations.filter((item) => item.subscriptionId === subscription.id);
    if (matching.length > 1) throw new UnprocessableEntityException({
      code: "DUPLICATE_SUBSCRIPTION_SELECTION", field: "clientDecisions",
    });
    const allocation = matching[0];
    if (!allocation && row.reservation_id && allocations.length) {
      // A transferred reserve can reference a replacement subscription while
      // the immutable decision still names its predecessor. Its lifecycle
      // command owns that mapping; do not undo it in chronological allocation.
      const predecessor = await client.query<{ inherited: boolean }>(`
        with recursive chain(id) as (
          select $1::uuid union
          select event.before_issued_subscription_id from app.subscription_lifecycle_events event
          join chain on chain.id = event.after_issued_subscription_id
          where event.event_type = 'replace' and event.before_issued_subscription_id is not null
        ) select exists(select 1 from chain where id = any($2::uuid[])) as inherited
      `, [subscription.id, allocations.map((item) => item.subscriptionId)]);
      if (predecessor.rows[0]?.inherited) { row.movable = false; continue; }
    }
    if (!allocation || allocation.clientType !== "student"
      || (allocation.payerStudentId ?? allocation.clientId) !== subscription.student_id
      || !(await coversLesson(row.id, allocation.clientId))) continue;
    const units = hundredths(allocation.units);
    if (units > 0) candidates.set(row.id, units);
  }
  let available = Math.max(0, hundredths(subscription.lessons_total)
    - hundredths(used.rows[0]?.units ?? 0)
    - rows.rows.filter((row) => !row.movable).reduce((sum, row) => sum + hundredths(row.reserved_units ?? 0), 0));
  const desired = new Map<string, number>();
  for (const [lessonId, units] of candidates) {
    if (units > 0 && units <= available) {
      desired.set(lessonId, units);
      available -= units;
    }
  }
  const released: string[] = [];
  const added: string[] = [];
  const changed = new Set<string>();
  for (const row of rows.rows) {
    if (!row.movable || !row.reservation_id) continue;
    if (desired.get(row.id) === hundredths(row.reserved_units ?? 0)) continue;
    const result = await client.query<{ id: string }>(`
      update app.lesson_reservations set state = 'released', financial_fact_id = null
      where id = $1 and state = 'reserved' returning id
    `, [row.reservation_id]);
    released.push(...result.rows.map((item) => item.id));
    changed.add(row.id);
  }
  for (const row of rows.rows) {
    const units = desired.get(row.id);
    if (units === undefined || (row.reservation_id && units === hundredths(row.reserved_units ?? 0))) continue;
    const result = await client.query<{ id: string }>(`
      insert into app.lesson_reservations (lesson_id, subscription_id, units)
      values ($1, $2, $3::numeric) returning id
    `, [row.id, subscription.id, (units / 100).toFixed(2)]);
    added.push(result.rows[0]!.id);
    changed.add(row.id);
  }
  if (changed.size) {
    const persistence = new PlatformIntegrityRepository();
    const requestId = `coverage-${randomUUID()}`;
    await persistence.appendAudit(client, {
      action: "crm.subscription_coverage_reconciled", entityType: "subscription",
      entityId: subscription.id, requestId, reason: "subscription.chronological-coverage",
      beforeRef: { reservationIds: released }, afterRef: { reservationIds: added },
      metadata: { lessonIds: [...changed], reviewRequiredLessonIds },
    });
    const version = await client.query<{ version: number }>(
      "select version from app.subscriptions where id = $1", [subscription.id]);
    for (const type of ["commerce.subscription.coverage.changed", "schedule.lessons.changed"]) {
      await persistence.enqueueOutbox(client, {
        type, aggregateType: "commerce:issued-subscription", aggregateId: subscription.id,
        aggregateVersion: Number(version.rows[0]!.version), requestId,
        payload: { subscriptionId: subscription.id, action: "coverage-reconciled", lessonIds: [...changed] },
      });
    }
  }
  return {
    coveredLessonIds: new Set([...desired.keys(), ...rows.rows.filter((row) => !row.movable && row.reservation_id).map((row) => row.id)]),
    changedLessonIds: [...changed], reviewRequiredLessonIds,
  };
}
