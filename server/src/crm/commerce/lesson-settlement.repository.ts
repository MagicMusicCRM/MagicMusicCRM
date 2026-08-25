import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { PoolClient } from "pg";
import {
  ClientChargeFactType,
  LessonSettlementInput,
  LessonFinancialDecision,
  LessonSettlementResult,
  PreparedLessonSettlementPlan,
  PlannedSubscriptionAllocation,
  StoredLessonSettlementPlan,
  TeacherCompensationFactType,
} from "./lesson-settlement.port";
import {
  calculateClientSettlement,
  calculateTeacherCompensation,
  rublesToMinor,
} from "./lesson-settlement.calculation";
import {
  assertPlannedLessonSettlementDecision,
  invalidLessonSettlementDecision,
  loadLessonSettlementCatalog,
  rethrowLessonSettlementCalculation,
} from "./lesson-settlement-catalog";
import {
  assignLessonSettlementPlan,
  cloneLessonSettlementPlan,
  insertPreparedLessonSettlementPlan,
  loadLessonSettlementPlan,
  markLessonSettlementPlanState,
  plannedLessonSubscriptionAllocations,
  prepareLessonSettlementPlan,
  replaceLessonSettlementPlan,
} from "./lesson-settlement-plan.persistence";
import {
  insertConfiguredLessonClientFacts,
  insertConfiguredLessonTeacherFact,
  insertLegacyLessonSettlementFacts,
  loadExcludedLessonParticipantIds,
  loadLessonSettlementCharges,
  loadLessonSettlementFacts,
  loadLessonSettlementSource,
  loadSupersededLessonFacts,
  type CalculatedLessonClientFact,
  type LessonSettlementChargeSource,
  type LessonSettlementSource,
} from "./lesson-settlement-facts.persistence";

@Injectable()
export class LessonSettlementRepository {
  async preparePlan(
    client: PoolClient,
    branchId: string,
    decision: LessonFinancialDecision,
  ): Promise<PreparedLessonSettlementPlan> {
    return prepareLessonSettlementPlan(client, branchId, decision);
  }

  async assignPlan(
    client: PoolClient,
    input: {
      lessonId: string;
      branchId: string;
      decision: LessonFinancialDecision;
      selectedBy: string;
      reasonText?: string;
    },
  ): Promise<PreparedLessonSettlementPlan> {
    return assignLessonSettlementPlan(client, input);
  }

  async clonePlan(
    client: PoolClient,
    input: {
      sourceLessonId: string;
      targetLessonId: string;
      selectedBy: string;
      reasonText?: string;
      fallback?: {
        branchId: string;
        decision: LessonFinancialDecision;
      };
    },
  ): Promise<PreparedLessonSettlementPlan> {
    return cloneLessonSettlementPlan(client, input);
  }

  async insertPreparedPlan(
    client: PoolClient,
    input: PreparedLessonSettlementPlan & {
      lessonId: string;
      selectedBy: string;
      reasonText?: string;
    },
  ): Promise<void> {
    return insertPreparedLessonSettlementPlan(client, input);
  }

  async plannedSubscriptionAllocations(
    client: PoolClient,
    lessonId: string,
    plan: PreparedLessonSettlementPlan,
  ): Promise<PlannedSubscriptionAllocation[]> {
    return plannedLessonSubscriptionAllocations(client, lessonId, plan);
  }

  async replacePlan(
    client: PoolClient,
    input: PreparedLessonSettlementPlan & {
      lessonId: string;
      expectedVersion: number;
      selectedBy: string;
      reasonText: string;
    },
  ): Promise<number> {
    return replaceLessonSettlementPlan(client, input);
  }

  async loadPlan(
    client: PoolClient,
    lessonId: string,
    lock = false,
  ): Promise<StoredLessonSettlementPlan | null> {
    return loadLessonSettlementPlan(client, lessonId, lock);
  }

  async markPlanState(
    client: PoolClient,
    lessonId: string,
    state: "settled" | "review_required" | "cancelled",
    failureCode?: string,
  ): Promise<void> {
    return markLessonSettlementPlanState(
      client,
      lessonId,
      state,
      failureCode,
    );
  }

  async settle(
    client: PoolClient,
    lessonId: string,
    input?: LessonSettlementInput,
  ): Promise<LessonSettlementResult> {
    await client.query(
      "select pg_advisory_xact_lock(hashtextextended($1, 0))",
      [`commerce:lesson-settlement:${lessonId}`],
    );

    const existing = await loadLessonSettlementFacts(client, lessonId);
    if (existing && !input?.correction) {
      if (input) await this.assertExistingDecision(client, existing, input);
      return existing;
    }

    const source = await loadLessonSettlementSource(client, lessonId);
    this.assertSettleable(source, input?.context);

    if (input) {
      await this.insertConfiguredFacts(client, source, input);
      const settled = await loadLessonSettlementFacts(client, lessonId);
      if (!settled) {
        throw new ConflictException({
          code: "LESSON_SETTLEMENT_INCOMPLETE",
          lessonId,
        });
      }
      return settled;
    }

    await insertLegacyLessonSettlementFacts(client, source);

    const settled = await loadLessonSettlementFacts(client, lessonId);
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
        from app.lesson_client_charge_facts_effective client_fact
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
      from app.lesson_teacher_compensation_facts_effective
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
    source: LessonSettlementSource,
    input: LessonSettlementInput,
  ): Promise<void> {
    if (input.reasonText && input.reasonText.trim().length > 500) {
      invalidLessonSettlementDecision("REASON_TOO_LONG", "reasonText");
    }
    const catalog = await loadLessonSettlementCatalog(
      client,
      source.branch_id,
      input.configurationRevisionIds,
    );
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
        invalidLessonSettlementDecision(
          "DUPLICATE_CLIENT_DECISION",
          "clientDecisions",
        );
      }
      clientDecisions.set(decision.clientId, decision);
    }

    const charges = await loadLessonSettlementCharges(client, source.lesson_id);
    const knownClients = new Set(charges.map((row) => row.client_id));
    const excludedClients = await loadExcludedLessonParticipantIds(
      client,
      source.lesson_id,
    );
    if ([...clientDecisions.keys()].some((id) =>
      !knownClients.has(id) && !excludedClients.has(id))) {
      invalidLessonSettlementDecision(
        "UNKNOWN_LESSON_CLIENT",
        "clientDecisions",
      );
    }

    const facts: CalculatedLessonClientFact[] = charges.map((charge) => {
      const decision = clientDecisions.get(charge.client_id);
      const settlementKey = decision?.settlementTypeKey ??
        input.decision.settlementTypeKey;
      const settlement = settlementTypes.get(settlementKey);
      if (!settlement || !settlement.allowedContexts.includes(input.context)) {
        invalidLessonSettlementDecision(
          "SETTLEMENT_TYPE_NOT_ALLOWED",
          "settlementTypeKey",
        );
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
        rethrowLessonSettlementCalculation(error);
      }
      return {
        charge,
        chargeType,
        subscriptionId: chargeType === "subscription" ? subscriptionId : null,
        settlement,
        calculation: calculation!,
      };
    });

    const superseded = await loadSupersededLessonFacts(
      client,
      source.lesson_id,
      Boolean(input.correction),
    );
    if (input.correction) {
      await this.lockCorrectionSubscriptionCapacity(
        client,
        source.lesson_id,
        facts,
      );
    } else {
      await this.lockAndReserveSubscriptions(client, source.lesson_id, facts);
    }
    await insertConfiguredLessonClientFacts(client, {
      lessonId: source.lesson_id,
      facts,
      configurationRevisionId: catalog.settlement_revision_id,
      correctionId: input.correction?.id ?? null,
      supersededFactIds: superseded.clientFactIds,
    });

    const rule = compensationRules.get(
      input.decision.teacherCompensationRuleKey,
    );
    if (!rule) {
      invalidLessonSettlementDecision(
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
      rethrowLessonSettlementCalculation(error);
    }
    await insertConfiguredLessonTeacherFact(client, {
      source,
      fact: { rule, calculation: teacher! },
      configurationRevisionId: catalog.compensation_revision_id,
      correctionId: input.correction?.id ?? null,
      supersededFactId: superseded.teacherFactId,
    });
  }

  private async lockAndReserveSubscriptions(
    client: PoolClient,
    lessonId: string,
    facts: Array<{
      charge: LessonSettlementChargeSource;
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
      invalidLessonSettlementDecision(
        "DUPLICATE_SUBSCRIPTION_SELECTION",
        "clientDecisions",
      );
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

  private async lockCorrectionSubscriptionCapacity(
    client: PoolClient,
    lessonId: string,
    facts: Array<{
      charge: LessonSettlementChargeSource;
      subscriptionId: string | null;
      calculation: { units: string; amountMinor: string };
    }>,
  ): Promise<void> {
    const selected = facts.filter(
      (fact) => fact.subscriptionId && Number(fact.calculation.units) > 0,
    );
    if (new Set(selected.map((fact) => fact.subscriptionId)).size !==
        selected.length) {
      invalidLessonSettlementDecision(
        "DUPLICATE_SUBSCRIPTION_SELECTION",
        "clientDecisions",
      );
    }
    for (const fact of selected.sort((left, right) =>
      left.subscriptionId!.localeCompare(right.subscriptionId!))) {
      const locked = await client.query<{
        student_id: string;
        status: string;
        is_usable: boolean;
        lessons_total: string;
        lessons_used: string;
      }>(
        `select student_id, status,
           (starts_at is null or starts_at <= current_date)
             and (expires_at is null or expires_at >= current_date)
             as is_usable,
           lessons_total::text, lessons_used::text
         from app.subscriptions where id = $1 for update`,
        [fact.subscriptionId],
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
        [fact.subscriptionId, lessonId],
      );
      const available = subscription
        ? Number(subscription.lessons_total) -
          Number(subscription.lessons_used) -
          Number(used.rows[0]?.settled ?? 0) -
          Number(used.rows[0]?.reserved ?? 0)
        : 0;
      if (!subscription || fact.charge.client_type !== "student" ||
          subscription.student_id !== fact.charge.client_id ||
          subscription.status !== "active" || !subscription.is_usable ||
          available + Number.EPSILON < Number(fact.calculation.units)) {
        throw new UnprocessableEntityException({
          code: "SUBSCRIPTION_CAPACITY",
          subscriptionId: fact.subscriptionId,
          clientId: fact.charge.client_id,
          requestedUnits: fact.calculation.units,
          availableUnits: Math.max(0, available).toFixed(2),
        });
      }
    }
  }

  private async assertExistingDecision(
    client: PoolClient,
    existing: LessonSettlementResult,
    input: LessonSettlementInput,
  ): Promise<void> {
    const excludedClients = await loadExcludedLessonParticipantIds(
      client,
      existing.lessonId,
    );
    const clients = new Map(
      (input.decision.clientDecisions ?? [])
        .filter((decision) => !excludedClients.has(decision.clientId))
        .map((decision) => [decision.clientId, decision]),
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

  private async loadExcludedParticipantIds(
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

  private assertSettleable(
    source: LessonSettlementSource,
    context?: LessonSettlementInput["context"],
  ) {
    const expectedState = context === "reschedule"
      ? "rescheduled"
      : context === "cancel"
        ? "cancelled"
        : "successfully_completed";
    if (source.lifecycle_state !== expectedState) {
      throw new ConflictException({
        code: "LESSON_NOT_IN_SETTLEMENT_STATE",
        lessonId: source.lesson_id,
        state: source.lifecycle_state,
        expectedState,
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
