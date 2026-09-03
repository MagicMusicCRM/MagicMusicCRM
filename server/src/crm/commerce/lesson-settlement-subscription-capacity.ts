import {
  ConflictException,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import { invalidLessonSettlementDecision } from "./lesson-settlement-catalog";
import type { CalculatedLessonClientFact } from "./lesson-settlement-facts.persistence";

/** Validate the selected owners even for free or not-yet-covered planned lessons. */
export async function assertLessonSubscriptionSelection(
  client: PoolClient,
  facts: CalculatedLessonClientFact[],
): Promise<void> {
  const selected = uniqueFactsBySubscription(facts.filter((fact) => fact.subscriptionId));
  for (const subscriptionId of [...selected.keys()].sort()) {
    const fact = selected.get(subscriptionId)!;
    const owner = await client.query<{ student_id: string }>(
      "select student_id from app.subscriptions where id = $1 for key share", [subscriptionId],
    );
    assertSubscriptionOwner(owner.rows[0]?.student_id, subscriptionId, fact, "0");
  }
}

export async function reserveLessonSettlementSubscriptions(
  client: PoolClient,
  lessonId: string,
  facts: CalculatedLessonClientFact[],
): Promise<void> {
  const factsBySubscription = uniqueFactsBySubscription(
    facts.filter((fact) => fact.subscriptionId),
  );
  for (const subscriptionId of [...factsBySubscription.keys()].sort()) {
    const fact = factsBySubscription.get(subscriptionId)!;
    await reserveLessonSubscription(client, lessonId, subscriptionId, fact);
  }
}

function uniqueFactsBySubscription(
  facts: CalculatedLessonClientFact[],
): Map<string, CalculatedLessonClientFact> {
  const mapped = new Map(
    facts.map((fact) => [fact.subscriptionId!, fact]),
  );
  if (mapped.size !== facts.length) {
    invalidLessonSettlementDecision(
      "DUPLICATE_SUBSCRIPTION_SELECTION",
      "clientDecisions",
    );
  }
  return mapped;
}

async function reserveLessonSubscription(
  client: PoolClient,
  lessonId: string,
  subscriptionId: string,
  fact: CalculatedLessonClientFact,
): Promise<void> {
  const locked = await client.query<{
    student_id: string;
    is_usable: boolean;
    has_capacity: boolean;
    available_units: string;
  }>(
    `
      select subscription.student_id,
        (
          subscription.status = 'active'
          and (
            subscription.starts_at is null
            or subscription.starts_at <= timezone(
              coalesce(series.timezone_name, branch.timezone_name, 'Europe/Moscow'),
              lesson.scheduled_at
            )::date
          )
          and (
            subscription.expires_at is null
            or subscription.expires_at >= timezone(
              coalesce(series.timezone_name, branch.timezone_name, 'Europe/Moscow'),
              lesson.scheduled_at
            )::date
          )
          and owner.deleted_at is null
          and owner.branch_id = lesson.branch_id
          and recipient.deleted_at is null
          and recipient.branch_id = lesson.branch_id
          and (package.branch_id is null or package.branch_id = lesson.branch_id)
        ) as is_usable,
        capacity.available_units::text,
        capacity.available_units >= $3::numeric as has_capacity
      from app.subscriptions subscription
      join app.students owner on owner.id = subscription.student_id
      join app.lessons lesson on lesson.id = $2 and lesson.deleted_at is null
      join app.students recipient on recipient.id = $4
      left join app.schedule_series series on series.id = lesson.series_id
      left join app.branches branch on branch.id = lesson.branch_id
      left join app.subscription_packages package on package.id = subscription.package_id
      cross join lateral (
        select (
          subscription.lessons_total - subscription.lessons_used
          - coalesce((
            select sum(charge.units)
            from app.lesson_client_charge_facts_effective charge
            where charge.subscription_id = subscription.id
              and charge.charge_type = 'subscription'
          ), 0)
          - coalesce((
            select sum(reservation.units)
            from app.lesson_reservations reservation
            where reservation.subscription_id = subscription.id
              and reservation.state = 'reserved'
              and reservation.lesson_id <> $2
          ), 0)
        ) as available_units
      ) capacity
      where subscription.id = $1
      for update of subscription
    `,
    [
      subscriptionId,
      lessonId,
      fact.calculation.units,
      fact.charge.client_id,
    ],
  );
  const subscription = locked.rows[0];
  const consumesUnits = fact.calculation.units !== "0.00";
  assertSubscriptionCanCover(
    subscription,
    subscriptionId,
    fact,
    consumesUnits,
  );
  if (!consumesUnits) return;
  let reservation = await client.query(
    `
      insert into app.lesson_reservations (lesson_id, subscription_id, units)
      values ($1, $2, $3::numeric)
      on conflict do nothing
      returning id
    `,
    [lessonId, subscriptionId, fact.calculation.units],
  );
  if (!reservation.rows[0]) {
    // The subscription lock serializes allocation. Only a live reservation
    // can be adjusted; released/consumed records remain historical facts.
    reservation = await client.query(
      `update app.lesson_reservations set units = $3::numeric
       where lesson_id = $1 and subscription_id = $2 and state = 'reserved'
       returning id`,
      [lessonId, subscriptionId, fact.calculation.units],
    );
  }
  if (!reservation.rows[0]) {
    throw new ConflictException({
      code: "SUBSCRIPTION_RESERVATION_TERMINAL",
      lessonId,
      subscriptionId,
    });
  }
}

function assertSubscriptionCanCover(
  subscription: {
    student_id: string;
    is_usable: boolean;
    has_capacity: boolean;
    available_units: string;
  } | undefined,
  subscriptionId: string,
  fact: CalculatedLessonClientFact,
  consumesUnits: boolean,
): void {
  assertSubscriptionOwner(subscription?.student_id, subscriptionId, fact, subscription?.available_units ?? "0");
  const hasCapacity =
    !consumesUnits ||
    (subscription?.is_usable === true && subscription.has_capacity === true);
  if (subscription && hasCapacity) return;
  throw new UnprocessableEntityException({
    code: "SUBSCRIPTION_CAPACITY",
    subscriptionId,
    clientId: fact.charge.client_id,
    payerStudentId: fact.payerStudentId,
    requestedUnits: fact.calculation.units,
    availableUnits: subscription?.available_units ?? "0",
  });
}

function assertSubscriptionOwner(
  ownerStudentId: string | undefined,
  subscriptionId: string,
  fact: CalculatedLessonClientFact,
  availableUnits: string,
): void {
  if (fact.charge.client_type === "student" &&
      ownerStudentId === (fact.payerStudentId ?? fact.charge.client_id)) return;
  throw new UnprocessableEntityException({
    code: "SUBSCRIPTION_CAPACITY", subscriptionId, clientId: fact.charge.client_id,
    payerStudentId: fact.payerStudentId, requestedUnits: fact.calculation.units,
    availableUnits,
  });
}

export async function assertCorrectionSubscriptionCapacity(
  client: PoolClient,
  lessonId: string,
  facts: CalculatedLessonClientFact[],
): Promise<void> {
  // Zero-unit corrections still retain a funding source and must bind its owner.
  for (const fact of facts.filter((item) => item.subscriptionId && Number(item.calculation.units) === 0)) {
    const owner = await client.query<{ student_id: string }>(
      "select student_id from app.subscriptions where id = $1 for key share",
      [fact.subscriptionId],
    );
    if (fact.charge.client_type !== "student" ||
        owner.rows[0]?.student_id !== (fact.payerStudentId ?? fact.charge.client_id)) {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_CAPACITY",
        subscriptionId: fact.subscriptionId,
        clientId: fact.charge.client_id,
        payerStudentId: fact.payerStudentId,
        requestedUnits: fact.calculation.units,
        availableUnits: "0",
      });
    }
  }
  const selected = facts.filter(
    (fact) => fact.subscriptionId && Number(fact.calculation.units) > 0,
  );
  const factsBySubscription = uniqueFactsBySubscription(selected);
  for (const subscriptionId of [...factsBySubscription.keys()].sort()) {
    await assertCorrectionSubscription(
      client,
      lessonId,
      subscriptionId,
      factsBySubscription.get(subscriptionId)!,
    );
  }
}

async function assertCorrectionSubscription(
  client: PoolClient,
  lessonId: string,
  subscriptionId: string,
  fact: CalculatedLessonClientFact,
): Promise<void> {
  const locked = await client.query<{
    student_id: string;
    status: string;
    is_usable: boolean;
    lessons_total: string;
    lessons_used: string;
  }>(
    `select subscription.student_id, subscription.status,
       (subscription.starts_at is null or subscription.starts_at <= timezone(
          coalesce(series.timezone_name, branch.timezone_name, 'Europe/Moscow'),
          lesson.scheduled_at
        )::date)
         and (subscription.expires_at is null or subscription.expires_at >= timezone(
          coalesce(series.timezone_name, branch.timezone_name, 'Europe/Moscow'),
          lesson.scheduled_at
        )::date)
         and owner.deleted_at is null
         and owner.branch_id = lesson.branch_id
         and recipient.deleted_at is null
         and recipient.branch_id = lesson.branch_id
         and (package.branch_id is null or package.branch_id = lesson.branch_id)
         as is_usable,
       subscription.lessons_total::text, subscription.lessons_used::text
     from app.subscriptions subscription
     join app.students owner on owner.id = subscription.student_id
     join app.lessons lesson on lesson.id = $2 and lesson.deleted_at is null
     join app.students recipient on recipient.id = $3
     left join app.schedule_series series on series.id = lesson.series_id
     left join app.branches branch on branch.id = lesson.branch_id
     left join app.subscription_packages package on package.id = subscription.package_id
     where subscription.id = $1 for update of subscription`,
    [subscriptionId, lessonId, fact.charge.client_id],
  );
  const subscription = locked.rows[0];
  const used = await client.query<{ settled: string; reserved: string }>(
    `select
       coalesce((select sum(units)
         from app.lesson_client_charge_facts_effective
         where subscription_id = $1 and charge_type = 'subscription'
           and lesson_id <> $2), 0)::text as settled,
       coalesce((select sum(units) from app.lesson_reservations
         where subscription_id = $1 and state = 'reserved'
           and lesson_id <> $2), 0)::text as reserved`,
    [subscriptionId, lessonId],
  );
  const available = availableCorrectionUnits(subscription, used.rows[0]);
  assertCorrectionCanCover(subscription, subscriptionId, fact, available);
}

function availableCorrectionUnits(
  subscription:
    | { lessons_total: string; lessons_used: string }
    | undefined,
  used: { settled: string; reserved: string } | undefined,
): number {
  if (!subscription) return 0;
  return (
    Number(subscription.lessons_total) -
    Number(subscription.lessons_used) -
    Number(used?.settled ?? 0) -
    Number(used?.reserved ?? 0)
  );
}

function assertCorrectionCanCover(
  subscription: {
    student_id: string;
    status: string;
    is_usable: boolean;
  } | undefined,
  subscriptionId: string,
  fact: CalculatedLessonClientFact,
  available: number,
): void {
  const valid =
    subscription?.student_id ===
      (fact.payerStudentId ?? fact.charge.client_id) &&
    fact.charge.client_type === "student" &&
    subscription.status === "active" &&
    subscription.is_usable &&
    available + Number.EPSILON >= Number(fact.calculation.units);
  if (valid) return;
  throw new UnprocessableEntityException({
    code: "SUBSCRIPTION_CAPACITY",
    subscriptionId,
    clientId: fact.charge.client_id,
    payerStudentId: fact.payerStudentId,
    requestedUnits: fact.calculation.units,
    availableUnits: Math.max(0, available).toFixed(2),
  });
}
