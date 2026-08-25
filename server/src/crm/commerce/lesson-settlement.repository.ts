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

@Injectable()
export class LessonSettlementRepository {
  async preparePlan(
    client: PoolClient,
    branchId: string,
    decision: LessonFinancialDecision,
  ): Promise<PreparedLessonSettlementPlan> {
    const catalog = await loadLessonSettlementCatalog(client, branchId);
    assertPlannedLessonSettlementDecision(catalog, decision);
    return {
      decision: JSON.parse(JSON.stringify(decision)) as LessonFinancialDecision,
      settlementRevisionId: catalog.settlement_revision_id,
      compensationRevisionId: catalog.compensation_revision_id,
    };
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
    const prepared = await this.preparePlan(
      client,
      input.branchId,
      input.decision,
    );
    await this.insertPreparedPlan(client, {
      lessonId: input.lessonId,
      selectedBy: input.selectedBy,
      reasonText: input.reasonText,
      ...prepared,
    });
    return prepared;
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
    const source = await this.loadPlan(client, input.sourceLessonId, true);
    if (!source && !input.fallback) {
      throw new ConflictException({
        code: "LESSON_SETTLEMENT_PLAN_MISSING",
        lessonId: input.sourceLessonId,
      });
    }
    const prepared: PreparedLessonSettlementPlan = source
      ? {
          decision: source.decision,
          settlementRevisionId: source.settlementRevisionId,
          compensationRevisionId: source.compensationRevisionId,
        }
      : await this.preparePlan(
          client,
          input.fallback!.branchId,
          input.fallback!.decision,
        );
    await this.insertPreparedPlan(client, {
      lessonId: input.targetLessonId,
      selectedBy: input.selectedBy,
      reasonText: input.reasonText ?? source?.reasonText ?? undefined,
      ...prepared,
    });
    return prepared;
  }

  async insertPreparedPlan(
    client: PoolClient,
    input: PreparedLessonSettlementPlan & {
      lessonId: string;
      selectedBy: string;
      reasonText?: string;
    },
  ): Promise<void> {
    const result = await client.query(
      `
        insert into app.lesson_settlement_plans (
          lesson_id, decision, settlement_revision_id,
          compensation_revision_id, selected_by, reason_text
        ) values ($1, $2::jsonb, $3, $4, $5, $6)
        on conflict (lesson_id) do nothing
        returning lesson_id
      `,
      [
        input.lessonId,
        JSON.stringify(input.decision),
        input.settlementRevisionId,
        input.compensationRevisionId,
        input.selectedBy,
        input.reasonText?.trim() || null,
      ],
    );
    if (!result.rows[0]) {
      throw new ConflictException({
        code: "LESSON_SETTLEMENT_PLAN_EXISTS",
        lessonId: input.lessonId,
      });
    }
    await client.query(
      `insert into app.lesson_settlement_plan_revisions (
         lesson_id, version, decision, settlement_revision_id,
         compensation_revision_id, reason_text, actor_user_id
       ) values ($1, 1, $2::jsonb, $3, $4, $5, $6)`,
      [
        input.lessonId,
        JSON.stringify(input.decision),
        input.settlementRevisionId,
        input.compensationRevisionId,
        input.reasonText?.trim() || null,
        input.selectedBy,
      ],
    );
  }

  async plannedSubscriptionAllocations(
    client: PoolClient,
    lessonId: string,
    plan: PreparedLessonSettlementPlan,
  ): Promise<PlannedSubscriptionAllocation[]> {
    const catalog = await loadLessonSettlementCatalog(client, "", {
      settlementRevisionId: plan.settlementRevisionId,
      compensationRevisionId: plan.compensationRevisionId,
    });
    assertPlannedLessonSettlementDecision(catalog, plan.decision);
    const duration = await client.query<{ duration_minutes: number }>(
      `select duration_minutes from app.lessons
       where id = $1 and deleted_at is null`,
      [lessonId],
    );
    if (!duration.rows[0]) throw new NotFoundException("Урок не найден.");
    const charges = await client.query<ChargeSourceRow>(
      `select snapshot.client_type, snapshot.client_id,
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
       order by client_type, client_id`,
      [lessonId],
    );
    const decisions = new Map(
      (plan.decision.clientDecisions ?? []).map((item) => [item.clientId, item]),
    );
    const settlementTypes = new Map(
      catalog.settlement_types.map((item) => [item.stableKey, item]),
    );
    return charges.rows.flatMap((charge) => {
      const selected = decisions.get(charge.client_id);
      const subscriptionId = selected?.subscriptionId ?? charge.subscription_id;
      const settlement = settlementTypes.get(
        selected?.settlementTypeKey ?? plan.decision.settlementTypeKey,
      );
      if (!settlement) {
        invalidLessonSettlementDecision(
          "SETTLEMENT_TYPE_NOT_ALLOWED",
          "settlementTypeKey",
        );
      }
      const chargeType: ClientChargeFactType = subscriptionId
        ? "subscription"
        : charge.charge_type;
      let calculated;
      try {
        calculated = calculateClientSettlement({
          durationMinutes: duration.rows[0]!.duration_minutes,
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
      if (chargeType !== "subscription" || !subscriptionId) return [];
      const units = Number(calculated.units);
      return units > 0
        ? [{
            clientType: charge.client_type,
            clientId: charge.client_id,
            subscriptionId,
            units,
          }]
        : [];
    });
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
    const result = await client.query<{ version: number | string }>(
      `update app.lesson_settlement_plans
       set decision = $3::jsonb,
           settlement_revision_id = $4,
           compensation_revision_id = $5,
           selected_by = $6,
           selected_at = now(),
           reason_text = $7,
           failure_code = null,
           version = version + 1,
           updated_at = now()
       where lesson_id = $1 and version = $2 and state = 'planned'
       returning version`,
      [
        input.lessonId,
        input.expectedVersion,
        JSON.stringify(input.decision),
        input.settlementRevisionId,
        input.compensationRevisionId,
        input.selectedBy,
        input.reasonText.trim(),
      ],
    );
    if (!result.rows[0]) {
      throw new ConflictException({ code: "LESSON_SETTLEMENT_PLAN_STALE" });
    }
    const version = Number(result.rows[0].version);
    await client.query(
      `insert into app.lesson_settlement_plan_revisions (
         lesson_id, version, decision, settlement_revision_id,
         compensation_revision_id, reason_text, actor_user_id
       ) values ($1, $2, $3::jsonb, $4, $5, $6, $7)`,
      [
        input.lessonId,
        version,
        JSON.stringify(input.decision),
        input.settlementRevisionId,
        input.compensationRevisionId,
        input.reasonText.trim(),
        input.selectedBy,
      ],
    );
    return version;
  }

  async loadPlan(
    client: PoolClient,
    lessonId: string,
    lock = false,
  ): Promise<StoredLessonSettlementPlan | null> {
    const result = await client.query<{
      lesson_id: string;
      decision: LessonFinancialDecision;
      settlement_revision_id: string;
      compensation_revision_id: string;
      version: number | string;
      state: StoredLessonSettlementPlan["state"];
      reason_text: string | null;
    }>(
      `select lesson_id, decision, settlement_revision_id,
         compensation_revision_id, version, state, reason_text
       from app.lesson_settlement_plans where lesson_id = $1
       ${lock ? "for update" : ""}`,
      [lessonId],
    );
    const row = result.rows[0];
    return row
      ? {
          lessonId: row.lesson_id,
          decision: row.decision,
          settlementRevisionId: row.settlement_revision_id,
          compensationRevisionId: row.compensation_revision_id,
          version: Number(row.version),
          state: row.state,
          reasonText: row.reason_text,
        }
      : null;
  }

  async markPlanState(
    client: PoolClient,
    lessonId: string,
    state: "settled" | "review_required" | "cancelled",
    failureCode?: string,
  ): Promise<void> {
    const result = await client.query(
      `update app.lesson_settlement_plans
       set state = $2,
           failure_code = case when $2 = 'review_required' then $3 else null end,
           version = version + 1,
           updated_at = now()
       where lesson_id = $1
         and state in ('planned', 'review_required')
       returning lesson_id`,
      [lessonId, state, failureCode?.trim().slice(0, 120) || null],
    );
    if (!result.rows[0]) {
      throw new ConflictException({
        code: "LESSON_SETTLEMENT_PLAN_STATE",
        lessonId,
      });
    }
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

    const existing = await this.loadFacts(client, lessonId);
    if (existing && !input?.correction) {
      if (input) await this.assertExistingDecision(client, existing, input);
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
    this.assertSettleable(source, input?.context);

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
    source: SettlementSourceRow,
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
          and not exists (
            select 1 from app.lesson_participant_exclusions exclusion
            where exclusion.lesson_id = participant.lesson_id
              and exclusion.student_id = participant.student_id
          )
        order by client_type, client_id
      `,
      [source.lesson_id],
    );
    const knownClients = new Set(chargesResult.rows.map((row) => row.client_id));
    const excludedClients = await this.loadExcludedParticipantIds(
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

    const facts = chargesResult.rows.map((charge) => {
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

    const supersededClients = input.correction
      ? new Map((await client.query<{ id: string; client_id: string }>(
          `select id, client_id
           from app.lesson_client_charge_facts_effective
           where lesson_id = $1`,
          [source.lesson_id],
        )).rows.map((row) => [row.client_id, row.id]))
      : new Map<string, string>();
    const supersededTeacher = input.correction
      ? (await client.query<{ id: string }>(
          `select id from app.lesson_teacher_compensation_facts_effective
           where lesson_id = $1`,
          [source.lesson_id],
        )).rows[0]?.id ?? null
      : null;
    if (input.correction) {
      await this.lockCorrectionSubscriptionCapacity(
        client,
        source.lesson_id,
        facts,
      );
    } else {
      await this.lockAndReserveSubscriptions(client, source.lesson_id, facts);
    }
    for (const fact of facts) {
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
          input.correction?.id ?? null,
          supersededClients.get(fact.charge.client_id) ?? null,
        ],
      );
    }

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
        input.correction?.id ?? null,
        supersededTeacher,
      ],
    );
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
      charge: ChargeSourceRow;
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
    const excludedClients = await this.loadExcludedParticipantIds(
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
    source: SettlementSourceRow,
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
