import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { PoolClient } from "pg";
import {
  LessonSettlementTypeConfig,
  TeacherCompensationRuleConfig,
} from "../crm-configuration.service";
import {
  ClientChargeFactType,
  LessonSettlementInput,
  LessonSettlementResult,
  TeacherCompensationFactType,
} from "./lesson-settlement.port";
import {
  calculateClientSettlement,
  calculateTeacherCompensation,
  LessonSettlementCalculationError,
  rublesToMinor,
} from "./lesson-settlement.calculation";

interface SettlementSourceRow {
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

interface ChargeSourceRow {
  client_type: "lead" | "student";
  client_id: string;
  charge_type: ClientChargeFactType;
  charge_value: string;
  subscription_id: string | null;
}

interface CommerceCatalogRow {
  settlement_revision_id: string;
  compensation_revision_id: string;
  settlement_types: LessonSettlementTypeConfig[];
  compensation_rules: TeacherCompensationRuleConfig[];
}

@Injectable()
export class LessonSettlementRepository {
  async settle(
    client: PoolClient,
    lessonId: string,
    input?: LessonSettlementInput,
  ): Promise<LessonSettlementResult> {
    await client.query(
      "select pg_advisory_xact_lock(hashtextextended($1, 0))",
      [`commerce:lesson-settlement:${lessonId}`],
    );

    const existing = await this.loadFacts(client, lessonId);
    if (existing) {
      if (input) this.assertExistingDecision(existing, input);
      return existing;
    }

    const sourceResult = await client.query<SettlementSourceRow>(
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
          snapshot.validation_state
          ,(
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
    this.assertSettleable(source);

    if (input) {
      await this.insertConfiguredFacts(client, source, input);
      const settled = await this.loadFacts(client, lessonId);
      if (!settled) {
        throw new ConflictException({
          code: "LESSON_SETTLEMENT_INCOMPLETE",
          lessonId,
        });
      }
      return settled;
    }

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
      [lessonId],
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
        lessonId,
        source.teacher_id,
        source.teacher_compensation_type,
        source.teacher_compensation_value,
        source.duration_minutes,
      ],
    );

    const settled = await this.loadFacts(client, lessonId);
    if (!settled) {
      throw new ConflictException({
        code: "LESSON_SETTLEMENT_INCOMPLETE",
        lessonId,
      });
    }
    return settled;
  }

  private async loadFacts(
    client: PoolClient,
    lessonId: string,
  ): Promise<LessonSettlementResult | null> {
    const clientFacts = await client.query<{
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
    }>(
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
        from app.lesson_client_charge_facts client_fact
        where client_fact.lesson_id = $1
        order by client_fact.client_type, client_fact.client_id
      `,
      [lessonId],
    );
    const teacherFacts = await client.query<{
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
    }>(`
      select id as teacher_fact_id, teacher_id, compensation_type,
        snapshot_rate as teacher_snapshot_rate, rate_minor, duration_minutes,
        amount_minor as teacher_amount_minor, currency_code as teacher_currency_code,
        compensation_rule_key, compensation_rule_label, compensation_mode,
        compensation_default_value, compensation_actual_value,
        compensation_override_reason, configuration_revision_id
      from app.lesson_teacher_compensation_facts
      where lesson_id = $1
    `, [lessonId]);
    if (clientFacts.rows.length === 0 && teacherFacts.rows.length === 0) return null;
    const invalidClient = clientFacts.rows.some((row) =>
      !row.client_fact_id || !row.client_type || !row.client_id ||
      !row.charge_type || row.client_snapshot_value === null ||
      row.client_amount_minor === null || row.units === null ||
      !row.client_currency_code,
    );
    const teacher = teacherFacts.rows[0];
    if (invalidClient || clientFacts.rows.length === 0 || !teacher) {
      throw new ConflictException({
        code: "PARTIAL_LESSON_SETTLEMENT",
        lessonId,
      });
    }
    const normalizedClientFacts = clientFacts.rows.map((row) => ({
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
      hourShareBasisPoints: row.hour_share_basis_points === null
        ? null
        : Number(row.hour_share_basis_points),
      fixedPenaltyMinor: row.fixed_penalty_minor,
      configurationRevisionId: row.configuration_revision_id,
    }));
    return {
      lessonId,
      clientFacts: normalizedClientFacts,
      clientFact: normalizedClientFacts[0]!,
      teacherFact: {
        id: teacher.teacher_fact_id,
        teacherId: teacher.teacher_id,
        compensationType: teacher.compensation_type,
        snapshotRate: teacher.teacher_snapshot_rate,
        rateMinor: teacher.rate_minor,
        durationMinutes: Number(teacher.duration_minutes),
        amountMinor: teacher.teacher_amount_minor,
        currencyCode: teacher.teacher_currency_code,
        compensationRuleKey: teacher.compensation_rule_key,
        compensationRuleLabel: teacher.compensation_rule_label,
        compensationMode: teacher.compensation_mode,
        compensationDefaultValue: teacher.compensation_default_value,
        compensationActualValue: teacher.compensation_actual_value,
        compensationOverrideReason: teacher.compensation_override_reason,
        configurationRevisionId: teacher.configuration_revision_id,
      },
    };
  }

  private async insertConfiguredFacts(
    client: PoolClient,
    source: SettlementSourceRow,
    input: LessonSettlementInput,
  ): Promise<void> {
    if (input.reasonText && input.reasonText.trim().length > 500) {
      this.invalidDecision("REASON_TOO_LONG", "reasonText");
    }
    const catalog = await this.loadCatalog(client, source.branch_id);
    const settlementTypes = new Map(
      catalog.settlement_types.filter((type) => type.active)
        .map((type) => [type.stableKey, type]),
    );
    const compensationRules = new Map(
      catalog.compensation_rules.filter((rule) => rule.active)
        .map((rule) => [rule.stableKey, rule]),
    );
    const clientDecisions = new Map<string, NonNullable<
      LessonSettlementInput["decision"]["clientDecisions"]
    >[number]>();
    for (const decision of input.decision.clientDecisions ?? []) {
      if (clientDecisions.has(decision.clientId)) {
        this.invalidDecision("DUPLICATE_CLIENT_DECISION", "clientDecisions");
      }
      clientDecisions.set(decision.clientId, decision);
    }

    const chargesResult = await client.query<ChargeSourceRow>(
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
        order by client_type, client_id
      `,
      [source.lesson_id],
    );
    const knownClients = new Set(chargesResult.rows.map((row) => row.client_id));
    if ([...clientDecisions.keys()].some((id) => !knownClients.has(id))) {
      this.invalidDecision("UNKNOWN_LESSON_CLIENT", "clientDecisions");
    }

    const facts = chargesResult.rows.map((charge) => {
      const decision = clientDecisions.get(charge.client_id);
      const settlementKey = decision?.settlementTypeKey ??
        input.decision.settlementTypeKey;
      const settlement = settlementTypes.get(settlementKey);
      if (!settlement || !settlement.allowedContexts.includes(input.context)) {
        this.invalidDecision("SETTLEMENT_TYPE_NOT_ALLOWED", "settlementTypeKey");
      }
      const subscriptionId = decision?.subscriptionId ?? charge.subscription_id;
      const chargeType: ClientChargeFactType = subscriptionId
        ? "subscription"
        : charge.charge_type;
      let calculation;
      try {
        calculation = calculateClientSettlement({
          durationMinutes: source.duration_minutes!,
          hourShareBasisPoints: settlement.hourShareBasisPoints,
          fixedPenaltyMinor: settlement.fixedPenaltyMinor ?? "0",
          chargeType,
          baseChargeMinor: chargeType === "personal_account"
            ? rublesToMinor(charge.charge_value)
            : 0n,
        });
      } catch (error) {
        this.rethrowCalculation(error);
      }
      return {
        charge,
        chargeType,
        subscriptionId: chargeType === "subscription" ? subscriptionId : null,
        settlement,
        calculation: calculation!,
      };
    });

    await this.lockAndReserveSubscriptions(client, source.lesson_id, facts);
    for (const fact of facts) {
      await client.query(
        `
          insert into app.lesson_client_charge_facts (
            lesson_id, client_type, client_id, charge_type, snapshot_value,
            subscription_id, amount_minor, units, settlement_type_key,
            settlement_label, settlement_color_token,
            hour_share_basis_points, fixed_penalty_minor,
            configuration_revision_id
          ) values (
            $1, $2, $3, $4, $5::numeric, $6, $7::bigint, $8::numeric,
            $9, $10, $11, $12, $13::bigint, $14
          )
        `,
        [
          source.lesson_id,
          fact.charge.client_type,
          fact.charge.client_id,
          fact.chargeType,
          fact.chargeType === "subscription"
            ? fact.calculation.units
            : fact.chargeType === "personal_account"
              ? fact.charge.charge_value
              : "0",
          fact.subscriptionId,
          fact.calculation.amountMinor,
          fact.calculation.units,
          fact.settlement.stableKey,
          fact.settlement.label,
          fact.settlement.colorToken,
          fact.settlement.hourShareBasisPoints,
          fact.settlement.fixedPenaltyMinor ?? "0",
          catalog.settlement_revision_id,
        ],
      );
    }

    const rule = compensationRules.get(
      input.decision.teacherCompensationRuleKey,
    );
    if (!rule) {
      this.invalidDecision(
        "TEACHER_COMPENSATION_RULE_NOT_FOUND",
        "teacherCompensationRuleKey",
      );
    }
    let teacher;
    try {
      teacher = calculateTeacherCompensation({
        durationMinutes: source.duration_minutes!,
        legacyType: source.teacher_compensation_type!,
        legacyRateRubles: source.teacher_compensation_value!,
        mode: rule.mode,
        configuredValue: rule.value,
        overrideValue: input.decision.teacherCompensationValueMinor,
        overrideReason: input.reasonText,
      });
    } catch (error) {
      this.rethrowCalculation(error);
    }
    await client.query(
      `
        insert into app.lesson_teacher_compensation_facts (
          lesson_id, teacher_id, compensation_type, snapshot_rate,
          rate_minor, duration_minutes, amount_minor,
          compensation_rule_key, compensation_rule_label, compensation_mode,
          compensation_default_value, compensation_actual_value,
          compensation_override_reason, configuration_revision_id
        ) values (
          $1, $2, $3, $4::numeric, $5::bigint, $6, $7::bigint,
          $8, $9, $3, $10::bigint, $11::bigint, $12, $13
        )
      `,
      [
        source.lesson_id,
        source.teacher_id,
        rule.mode,
        teacher!.snapshotRate,
        teacher!.rateMinor,
        source.duration_minutes,
        teacher!.amountMinor,
        rule.stableKey,
        rule.label,
        teacher!.defaultValue,
        teacher!.actualValue,
        teacher!.overrideReason,
        catalog.compensation_revision_id,
      ],
    );
  }

  private async loadCatalog(
    client: PoolClient,
    branchId: string,
  ): Promise<CommerceCatalogRow> {
    const result = await client.query<CommerceCatalogRow>(
      `
        with school as (
          select id, effective_snapshot
          from app.crm_configuration_revisions
          where branch_id is null order by version desc limit 1
        ), branch as (
          select id, patch
          from app.crm_configuration_revisions
          where branch_id = $1 order by version desc limit 1
        )
        select
          case when branch.patch ? 'lessonSettlementTypes'
            then branch.id else school.id end as settlement_revision_id,
          case when branch.patch ? 'teacherCompensationRules'
            then branch.id else school.id end as compensation_revision_id,
          coalesce(
            branch.patch->'lessonSettlementTypes',
            school.effective_snapshot->'lessonSettlementTypes'
          ) as settlement_types,
          coalesce(
            branch.patch->'teacherCompensationRules',
            school.effective_snapshot->'teacherCompensationRules'
          ) as compensation_rules
        from school left join branch on true
      `,
      [branchId],
    );
    const catalog = result.rows[0];
    if (!catalog || !Array.isArray(catalog.settlement_types) ||
        !Array.isArray(catalog.compensation_rules)) {
      throw new ConflictException({ code: "COMMERCE_CATALOG_NOT_PUBLISHED" });
    }
    return catalog;
  }

  private async lockAndReserveSubscriptions(
    client: PoolClient,
    lessonId: string,
    facts: Array<{
      charge: ChargeSourceRow;
      subscriptionId: string | null;
      calculation: { units: string; amountMinor: string };
    }>,
  ): Promise<void> {
    const chargeBySubscription = new Map(
      facts.filter((fact) => fact.subscriptionId)
        .map((fact) => [fact.subscriptionId!, fact]),
    );
    if (chargeBySubscription.size !==
        facts.filter((fact) => fact.subscriptionId).length) {
      this.invalidDecision("DUPLICATE_SUBSCRIPTION_SELECTION", "clientDecisions");
    }
    for (const subscriptionId of [...chargeBySubscription.keys()].sort()) {
      const fact = chargeBySubscription.get(subscriptionId)!;
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
                subscription.expires_at is null
                or subscription.expires_at >= current_date
              )
            ) as is_usable,
            capacity.available_units::text,
            capacity.available_units >= $3::numeric as has_capacity
          from app.subscriptions subscription
          cross join lateral (
            select (
              subscription.lessons_total - subscription.lessons_used
              - coalesce((
                select sum(charge.units)
                from app.lesson_client_charge_facts charge
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
          for update
        `,
        [subscriptionId, lessonId, fact.calculation.units],
      );
      const subscription = locked.rows[0];
      const consumesUnits = fact.calculation.units !== "0.00";
      if (
        !subscription ||
        fact.charge.client_type !== "student" ||
        subscription.student_id !== fact.charge.client_id ||
        (consumesUnits &&
          (!subscription.is_usable || !subscription.has_capacity))
      ) {
        throw new UnprocessableEntityException({
          code: "SUBSCRIPTION_CAPACITY",
          subscriptionId,
          clientId: fact.charge.client_id,
          requestedUnits: fact.calculation.units,
          availableUnits: subscription?.available_units ?? "0",
        });
      }
      if (!consumesUnits) continue;
      const reservation = await client.query(
        `
          insert into app.lesson_reservations (lesson_id, subscription_id, units)
          values ($1, $2, $3::numeric)
          on conflict (lesson_id, subscription_id) do update
            set units = excluded.units
            where app.lesson_reservations.state = 'reserved'
          returning id
        `,
        [lessonId, subscriptionId, fact.calculation.units],
      );
      if (!reservation.rows[0]) {
        throw new ConflictException({
          code: "SUBSCRIPTION_RESERVATION_TERMINAL",
          lessonId,
          subscriptionId,
        });
      }
    }
  }

  private assertExistingDecision(
    existing: LessonSettlementResult,
    input: LessonSettlementInput,
  ) {
    const clients = new Map(
      (input.decision.clientDecisions ?? []).map((decision) => [
        decision.clientId,
        decision,
      ]),
    );
    const existingClientIds = new Set(
      existing.clientFacts.map((fact) => fact.clientId),
    );
    const matches = [...clients.keys()].every((id) => existingClientIds.has(id)) &&
      existing.clientFacts.every((fact) => {
      const decision = clients.get(fact.clientId);
      return fact.settlementTypeKey === (
        decision?.settlementTypeKey ?? input.decision.settlementTypeKey
      ) && (!decision?.subscriptionId ||
        decision.subscriptionId === fact.subscriptionId);
      }) && existing.teacherFact.compensationRuleKey ===
      input.decision.teacherCompensationRuleKey &&
      (!input.decision.teacherCompensationValueMinor ||
        existing.teacherFact.compensationActualValue ===
          input.decision.teacherCompensationValueMinor);
    if (!matches) {
      throw new ConflictException({
        code: "LESSON_ALREADY_SETTLED_WITH_DIFFERENT_DECISION",
        lessonId: existing.lessonId,
      });
    }
  }

  private invalidDecision(code: string, field?: string): never {
    throw new UnprocessableEntityException({ code, field });
  }

  private rethrowCalculation(error: unknown): never {
    if (error instanceof LessonSettlementCalculationError) {
      this.invalidDecision(error.code);
    }
    throw error;
  }

  private assertSettleable(source: SettlementSourceRow) {
    if (source.lifecycle_state !== "successfully_completed") {
      throw new ConflictException({
        code: "LESSON_NOT_SUCCESSFULLY_COMPLETED",
        lessonId: source.lesson_id,
        state: source.lifecycle_state,
      });
    }
    if (
      source.validation_state !== "valid" ||
      !source.teacher_id ||
      !source.client_charge_type ||
      source.client_charge_value === null ||
      !source.teacher_compensation_type ||
      source.teacher_compensation_value === null ||
      !source.duration_minutes ||
      (source.group_id
        ? Number(source.participant_count) === 0
        : !source.client_type || !source.client_id)
    ) {
      throw new ConflictException({
        code: "LESSON_SETTLEMENT_SNAPSHOT_INCOMPLETE",
        lessonId: source.lesson_id,
      });
    }
  }
}
