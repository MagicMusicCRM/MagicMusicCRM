import { ConflictException, NotFoundException } from "@nestjs/common";
import type { PoolClient } from "pg";
import type {
  LessonSettlementTypeConfig,
  TeacherCompensationRuleConfig,
} from "../crm-configuration.contracts";
import type {
  ClientChargeFactType,
  LessonSettlementResult,
  TeacherCompensationFactType,
} from "./lesson-settlement.port";

export interface LessonSettlementSource {
  lesson_id: string;
  lifecycle_state: string;
  branch_id: string;
  teacher_id: string | null;
  group_id: string | null;
  client_type: "lead" | "student" | null;
  client_id: string | null;
  client_charge_type: ClientChargeFactType | null;
  client_charge_value: string | null;
  teacher_compensation_type: "fixed" | "hourly" | "none" | null;
  teacher_compensation_value: string | null;
  subscription_id: string | null;
  reservation_subscription_id: string | null;
  reservation_state: string | null;
  duration_minutes: number | null;
  validation_state: string | null;
  participant_count: number | string;
}

export interface LessonSettlementChargeSource {
  client_type: "lead" | "student";
  client_id: string;
  charge_type: ClientChargeFactType;
  charge_value: string;
  subscription_id: string | null;
}

export interface CalculatedLessonClientFact {
  charge: LessonSettlementChargeSource;
  chargeType: ClientChargeFactType;
  subscriptionId: string | null;
  settlement: LessonSettlementTypeConfig;
  calculation: { units: string; amountMinor: string };
}

export interface CalculatedLessonTeacherFact {
  rule: TeacherCompensationRuleConfig;
  calculation: {
    snapshotRate: string;
    rateMinor: string;
    amountMinor: string;
    defaultValue: string;
    actualValue: string;
    overrideReason: string | null;
  };
}

interface EffectiveClientFactRow {
  client_fact_id: string | null;
  client_type: "lead" | "student" | null;
  client_id: string | null;
  charge_type: ClientChargeFactType | null;
  client_snapshot_value: string | null;
  subscription_id: string | null;
  client_amount_minor: string | null;
  units: string | null;
  client_currency_code: string | null;
  settlement_type_key: string | null;
  settlement_label: string | null;
  settlement_color_token: string | null;
  hour_share_basis_points: number | null;
  fixed_penalty_minor: string | null;
  configuration_revision_id: string | null;
}

interface EffectiveTeacherFactRow {
  teacher_fact_id: string;
  teacher_id: string;
  compensation_type: TeacherCompensationFactType;
  teacher_snapshot_rate: string;
  rate_minor: string;
  duration_minutes: number;
  teacher_amount_minor: string;
  teacher_currency_code: string;
  compensation_rule_key: string | null;
  compensation_rule_label: string | null;
  compensation_mode: TeacherCompensationFactType | null;
  compensation_default_value: string | null;
  compensation_actual_value: string | null;
  compensation_override_reason: string | null;
  configuration_revision_id: string | null;
}

export async function loadLessonSettlementSource(
  client: PoolClient,
  lessonId: string,
): Promise<LessonSettlementSource> {
  const sourceResult = await client.query<LessonSettlementSource>(
    `
      select
        lesson.id as lesson_id,
        lesson.lifecycle_state,
        lesson.branch_id,
        lesson.teacher_id,
        snapshot.group_id,
        snapshot.client_type,
        snapshot.client_id,
        snapshot.client_charge_type,
        snapshot.client_charge_value,
        snapshot.teacher_compensation_type,
        snapshot.teacher_compensation_value,
        snapshot.subscription_id,
        reservation.subscription_id as reservation_subscription_id,
        reservation.state as reservation_state,
        snapshot.duration_minutes,
        snapshot.validation_state,
        (
          select count(*)
          from app.lesson_snapshot_participants participant
          where participant.lesson_id = lesson.id
        ) as participant_count
      from app.lessons lesson
      left join app.lesson_snapshots snapshot
        on snapshot.lesson_id = lesson.id
      left join lateral (
        select subscription_id, state
        from app.lesson_reservations
        where lesson_id = lesson.id
        order by created_at desc, id desc
        limit 1
      ) reservation on true
      where lesson.id = $1
        and lesson.deleted_at is null
      for update of lesson
    `,
    [lessonId],
  );
  const source = sourceResult.rows[0];
  if (!source) throw new NotFoundException("Урок не найден.");
  return source;
}

export async function loadLessonSettlementFacts(
  client: PoolClient,
  lessonId: string,
): Promise<LessonSettlementResult | null> {
  const clientFacts = await loadEffectiveClientFacts(client, lessonId);
  const teacherFacts = await loadEffectiveTeacherFacts(client, lessonId);
  if (clientFacts.length === 0 && teacherFacts.length === 0) return null;
  const teacher = teacherFacts[0];
  if (!hasCompleteClientFacts(clientFacts) || !teacher) {
    throw new ConflictException({
      code: "PARTIAL_LESSON_SETTLEMENT",
      lessonId,
    });
  }
  const normalizedClientFacts = clientFacts.map(mapEffectiveClientFact);
  return {
    lessonId,
    clientFacts: normalizedClientFacts,
    clientFact: normalizedClientFacts[0]!,
    teacherFact: mapEffectiveTeacherFact(teacher),
  };
}

async function loadEffectiveClientFacts(
  client: PoolClient,
  lessonId: string,
): Promise<EffectiveClientFactRow[]> {
  const result = await client.query<EffectiveClientFactRow>(
    `
      select
        client_fact.id as client_fact_id,
        client_fact.client_type,
        client_fact.client_id,
        client_fact.charge_type,
        client_fact.snapshot_value as client_snapshot_value,
        client_fact.subscription_id,
        client_fact.amount_minor as client_amount_minor,
        client_fact.units,
        client_fact.currency_code as client_currency_code,
        client_fact.settlement_type_key,
        client_fact.settlement_label,
        client_fact.settlement_color_token,
        client_fact.hour_share_basis_points,
        client_fact.fixed_penalty_minor,
        client_fact.configuration_revision_id
      from app.lesson_client_charge_facts_effective client_fact
      where client_fact.lesson_id = $1
      order by client_fact.client_type, client_fact.client_id
    `,
    [lessonId],
  );
  return result.rows;
}

async function loadEffectiveTeacherFacts(
  client: PoolClient,
  lessonId: string,
): Promise<EffectiveTeacherFactRow[]> {
  const result = await client.query<EffectiveTeacherFactRow>(
    `select id as teacher_fact_id, teacher_id, compensation_type,
       snapshot_rate as teacher_snapshot_rate, rate_minor, duration_minutes,
       amount_minor as teacher_amount_minor, currency_code as teacher_currency_code,
       compensation_rule_key, compensation_rule_label, compensation_mode,
       compensation_default_value, compensation_actual_value,
       compensation_override_reason, configuration_revision_id
     from app.lesson_teacher_compensation_facts_effective
     where lesson_id = $1`,
    [lessonId],
  );
  return result.rows;
}

function hasCompleteClientFacts(rows: EffectiveClientFactRow[]): boolean {
  if (rows.length === 0) return false;
  return rows.every(
    (row) =>
      Boolean(row.client_fact_id) &&
      Boolean(row.client_type) &&
      Boolean(row.client_id) &&
      Boolean(row.charge_type) &&
      row.client_snapshot_value !== null &&
      row.client_amount_minor !== null &&
      row.units !== null &&
      Boolean(row.client_currency_code),
  );
}

function mapEffectiveClientFact(
  row: EffectiveClientFactRow,
): LessonSettlementResult["clientFacts"][number] {
  return {
    id: row.client_fact_id!,
    clientType: row.client_type!,
    clientId: row.client_id!,
    chargeType: row.charge_type!,
    snapshotValue: row.client_snapshot_value!,
    subscriptionId: row.subscription_id,
    amountMinor: row.client_amount_minor!,
    units: row.units!,
    currencyCode: row.client_currency_code!,
    settlementTypeKey: row.settlement_type_key,
    settlementLabel: row.settlement_label,
    settlementColorToken: row.settlement_color_token,
    hourShareBasisPoints:
      row.hour_share_basis_points === null
        ? null
        : Number(row.hour_share_basis_points),
    fixedPenaltyMinor: row.fixed_penalty_minor,
    configurationRevisionId: row.configuration_revision_id,
  };
}

function mapEffectiveTeacherFact(
  row: EffectiveTeacherFactRow,
): LessonSettlementResult["teacherFact"] {
  return {
    id: row.teacher_fact_id,
    teacherId: row.teacher_id,
    compensationType: row.compensation_type,
    snapshotRate: row.teacher_snapshot_rate,
    rateMinor: row.rate_minor,
    durationMinutes: Number(row.duration_minutes),
    amountMinor: row.teacher_amount_minor,
    currencyCode: row.teacher_currency_code,
    compensationRuleKey: row.compensation_rule_key,
    compensationRuleLabel: row.compensation_rule_label,
    compensationMode: row.compensation_mode,
    compensationDefaultValue: row.compensation_default_value,
    compensationActualValue: row.compensation_actual_value,
    compensationOverrideReason: row.compensation_override_reason,
    configurationRevisionId: row.configuration_revision_id,
  };
}

export async function loadLessonSettlementCharges(
  client: PoolClient,
  lessonId: string,
): Promise<LessonSettlementChargeSource[]> {
  const result = await client.query<LessonSettlementChargeSource>(
    `
      select snapshot.client_type, snapshot.client_id,
        snapshot.client_charge_type as charge_type,
        snapshot.client_charge_value as charge_value,
        snapshot.subscription_id
      from app.lesson_snapshots snapshot
      where snapshot.lesson_id = $1 and snapshot.group_id is null
      union all
      select 'student'::text, participant.student_id,
        participant.charge_type, participant.charge_value,
        participant.subscription_id
      from app.lesson_snapshot_participants participant
      where participant.lesson_id = $1
        and not exists (
          select 1 from app.lesson_participant_exclusions exclusion
          where exclusion.lesson_id = participant.lesson_id
            and exclusion.student_id = participant.student_id
        )
      order by client_type, client_id
    `,
    [lessonId],
  );
  return result.rows;
}

export async function loadExcludedLessonParticipantIds(
  client: PoolClient,
  lessonId: string,
): Promise<Set<string>> {
  const result = await client.query<{ student_id: string }>(
    `select student_id
     from app.lesson_participant_exclusions
     where lesson_id = $1`,
    [lessonId],
  );
  return new Set(result.rows.map((row) => row.student_id));
}

export async function loadSupersededLessonFacts(
  client: PoolClient,
  lessonId: string,
  correction: boolean,
): Promise<{
  clientFactIds: Map<string, string>;
  teacherFactId: string | null;
}> {
  if (!correction) {
    return { clientFactIds: new Map(), teacherFactId: null };
  }
  const clients = await client.query<{ id: string; client_id: string }>(
    `select id, client_id
     from app.lesson_client_charge_facts_effective
     where lesson_id = $1`,
    [lessonId],
  );
  const teacher = await client.query<{ id: string }>(
    `select id from app.lesson_teacher_compensation_facts_effective
     where lesson_id = $1`,
    [lessonId],
  );
  return {
    clientFactIds: new Map(
      clients.rows.map((row) => [row.client_id, row.id]),
    ),
    teacherFactId: teacher.rows[0]?.id ?? null,
  };
}

export async function insertLegacyLessonSettlementFacts(
  client: PoolClient,
  source: LessonSettlementSource,
): Promise<void> {
  await client.query(
    `
      with charges as (
        select
          snapshot.client_type,
          snapshot.client_id,
          snapshot.client_charge_type as charge_type,
          snapshot.client_charge_value as charge_value,
          snapshot.subscription_id
        from app.lesson_snapshots snapshot
        where snapshot.lesson_id = $1 and snapshot.group_id is null
        union all
        select
          'student'::text,
          participant.student_id,
          participant.charge_type,
          participant.charge_value,
          participant.subscription_id
        from app.lesson_snapshot_participants participant
        where participant.lesson_id = $1
          and not exists (
            select 1 from app.lesson_participant_exclusions exclusion
            where exclusion.lesson_id = participant.lesson_id
              and exclusion.student_id = participant.student_id
          )
      ), effective as (
        select charges.*,
          case
            when charges.charge_type = 'subscription'
              and coverage.subscription_id is null then 'none'
            else charges.charge_type
          end as effective_charge_type,
          coverage.subscription_id as effective_subscription_id
        from charges
        left join lateral (
          select reservation.subscription_id
          from app.lesson_reservations reservation
          join app.subscriptions subscription
            on subscription.id = reservation.subscription_id
          where reservation.lesson_id = $1
            and reservation.state = 'reserved'
            and (
              reservation.subscription_id = charges.subscription_id
              or (
                charges.client_type = 'student'
                and subscription.student_id = charges.client_id
              )
            )
          order by
            (reservation.subscription_id = charges.subscription_id) desc,
            reservation.created_at,
            reservation.id
          limit 1
        ) coverage on charges.charge_type = 'subscription'
      )
      insert into app.lesson_client_charge_facts (
        lesson_id,
        client_type,
        client_id,
        charge_type,
        snapshot_value,
        subscription_id,
        amount_minor,
        units
      )
      select
        $1, client_type, client_id, effective_charge_type,
        case when effective_charge_type = 'none' then 0 else charge_value end,
        case when effective_charge_type = 'subscription'
          then effective_subscription_id else null end,
        case
          when effective_charge_type = 'personal_account'
            then round(charge_value * 100)::bigint
          else 0
        end,
        case
          when effective_charge_type = 'subscription' then charge_value
          else 0
        end
      from effective
      order by client_type, client_id
    `,
    [source.lesson_id],
  );
  await client.query(
    `
      insert into app.lesson_teacher_compensation_facts (
        lesson_id,
        teacher_id,
        compensation_type,
        snapshot_rate,
        rate_minor,
        duration_minutes,
        amount_minor
      )
      values (
        $1, $2, $3,
        case when $3 = 'none' then 0 else $4::text::numeric end,
        case
          when $3 = 'none' then 0
          else round($4::text::numeric * 100)::bigint
        end,
        $5::integer,
        case
          when $3 = 'fixed'
            then round($4::text::numeric * 100)::bigint
          when $3 = 'hourly'
            then round(
              $4::text::numeric * 100 * $5::integer / 60
            )::bigint
          else 0
        end
      )
    `,
    [
      source.lesson_id,
      source.teacher_id,
      source.teacher_compensation_type,
      source.teacher_compensation_value,
      source.duration_minutes,
    ],
  );
}

export async function insertConfiguredLessonClientFacts(
  client: PoolClient,
  input: {
    lessonId: string;
    facts: CalculatedLessonClientFact[];
    configurationRevisionId: string;
    correctionId: string | null;
    supersededFactIds: Map<string, string>;
  },
): Promise<void> {
  for (const fact of input.facts) {
    await client.query(
      `
        insert into app.lesson_client_charge_facts (
          lesson_id, client_type, client_id, charge_type, snapshot_value,
          subscription_id, amount_minor, units, settlement_type_key,
          settlement_label, settlement_color_token,
          hour_share_basis_points, fixed_penalty_minor,
          configuration_revision_id, correction_id, supersedes_fact_id
        ) values (
          $1, $2, $3, $4, $5::numeric, $6, $7::bigint, $8::numeric,
          $9, $10, $11, $12, $13::bigint, $14, $15, $16
        )
      `,
      [
        input.lessonId,
        fact.charge.client_type,
        fact.charge.client_id,
        fact.chargeType,
        snapshotFactValue(fact),
        fact.subscriptionId,
        fact.calculation.amountMinor,
        fact.calculation.units,
        fact.settlement.stableKey,
        fact.settlement.label,
        fact.settlement.colorToken,
        fact.settlement.hourShareBasisPoints,
        fact.settlement.fixedPenaltyMinor ?? "0",
        input.configurationRevisionId,
        input.correctionId,
        input.supersededFactIds.get(fact.charge.client_id) ?? null,
      ],
    );
  }
}

function snapshotFactValue(fact: CalculatedLessonClientFact): string {
  if (fact.chargeType === "subscription") return fact.calculation.units;
  if (fact.chargeType === "personal_account") return fact.charge.charge_value;
  return "0";
}

export async function insertConfiguredLessonTeacherFact(
  client: PoolClient,
  input: {
    source: LessonSettlementSource;
    fact: CalculatedLessonTeacherFact;
    configurationRevisionId: string;
    correctionId: string | null;
    supersededFactId: string | null;
  },
): Promise<void> {
  await client.query(
    `
      insert into app.lesson_teacher_compensation_facts (
        lesson_id, teacher_id, compensation_type, snapshot_rate,
        rate_minor, duration_minutes, amount_minor,
        compensation_rule_key, compensation_rule_label, compensation_mode,
        compensation_default_value, compensation_actual_value,
        compensation_override_reason, configuration_revision_id,
        correction_id, supersedes_fact_id
      ) values (
        $1, $2, $3, $4::numeric, $5::bigint, $6, $7::bigint,
        $8, $9, $3, $10::bigint, $11::bigint, $12, $13, $14, $15
      )
    `,
    [
      input.source.lesson_id,
      input.source.teacher_id,
      input.fact.rule.mode,
      input.fact.calculation.snapshotRate,
      input.fact.calculation.rateMinor,
      input.source.duration_minutes,
      input.fact.calculation.amountMinor,
      input.fact.rule.stableKey,
      input.fact.rule.label,
      input.fact.calculation.defaultValue,
      input.fact.calculation.actualValue,
      input.fact.calculation.overrideReason,
      input.configurationRevisionId,
      input.correctionId,
      input.supersededFactId,
    ],
  );
}
