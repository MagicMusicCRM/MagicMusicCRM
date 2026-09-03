import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash, randomUUID } from "node:crypto";
import { PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { LessonSettlementResult } from "../commerce/lesson-settlement.port";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { CrmPolicy } from "../crm.policy";
import { managerBranchScopeSql } from "../branch-scope";
import {
  LessonSettlementCorrectionCommandDto,
  LessonSettlementCorrectionPreviewDto,
} from "../dto/lesson-settlement-correction.dto";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import { applyLessonResourceEdit } from "./lesson-resource-edit";

@Injectable()
export class LessonSettlementCorrectionService {
  constructor(
    private readonly database: DatabaseService,
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly settlement: LessonSettlementService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
    private readonly reservations: SubscriptionReservationService,
    private readonly constraints: ScheduleConstraintEngine,
  ) {}

  async history(actor: ActorContext, lessonId: string) {
    this.policy.assertCanWriteCrm(actor);
    const lesson = await this.database.query<{
      id: string; can_read_teacher_compensation: boolean;
    }>(
      `select lesson.id,
         history_actor.role::text in ('director', 'system_admin')
           as can_read_teacher_compensation
       from app.lessons lesson
       join app.users history_actor on history_actor.id = $2
         and history_actor.deleted_at is null
         and history_actor.role::text in ('admin', 'manager', 'director', 'system_admin')
       where lesson.id = $1 and lesson.deleted_at is null
         and ${managerBranchScopeSql({
           roleExpression: "history_actor.role::text",
           userIdExpression: "$2",
           branchExpression: "lesson.branch_id::text",
         })}`,
      [lessonId, actor.userId],
    );
    if (!lesson.rows[0]) throw new NotFoundException("Урок не найден.");
    const history = await this.database.query<{
      kind: "planned" | "transition" | "correction";
      version: number | string;
      decision: Record<string, unknown>;
      reason_text: string | null;
      actor_user_id: string | null;
      actor_name: string;
      worker_id: string | null;
      created_at: Date | string;
      effective: boolean;
      settlement_type_label: string | null;
      teacher_compensation_rule_label: string | null;
    }>(
      `with latest_plan as (
         select max(version) as version
         from app.lesson_settlement_plan_revisions where lesson_id = $1
       ), latest_correction as (
         select max(version) as version
         from app.lesson_settlement_corrections where lesson_id = $1
       ), transitions as (
         select transition.*,
           row_number() over (order by transition.created_at, transition.id) as version
         from app.lesson_transitions transition
         where transition.lesson_id = $1 and transition.financial_decision <> '{}'::jsonb
       ), latest_transition as (
         select max(version) as version from transitions
       ), entries as (
         select 'planned'::text as kind, revision.version, revision.decision,
           revision.reason_text, revision.actor_user_id, null::text as worker_id,
           revision.created_at, revision.settlement_revision_id,
           revision.compensation_revision_id,
           (revision.version = latest_plan.version
             and latest_correction.version is null
             and latest_transition.version is null) as effective
         from app.lesson_settlement_plan_revisions revision
         cross join latest_plan cross join latest_correction cross join latest_transition
         where revision.lesson_id = $1
         union all
         select 'transition'::text, transition.version, transition.financial_decision,
           transition.reason_text, transition.actor_user_id, transition.worker_id,
           transition.created_at, client_fact.configuration_revision_id,
           teacher_fact.configuration_revision_id,
           (transition.version = latest_transition.version
             and latest_correction.version is null)
         from transitions transition
         cross join latest_transition cross join latest_correction
         left join app.lesson_client_charge_facts client_fact
           on client_fact.id = transition.client_financial_fact_id
         left join app.lesson_teacher_compensation_facts teacher_fact
           on teacher_fact.id = transition.teacher_financial_fact_id
         union all
         select 'correction'::text, correction.version, correction.decision,
           correction.reason_text, correction.actor_user_id, null::text,
           correction.created_at, correction.settlement_revision_id,
           correction.compensation_revision_id,
           correction.version = latest_correction.version
         from app.lesson_settlement_corrections correction
         cross join latest_correction
         where correction.lesson_id = $1
       )
       select entries.*,
         trim(coalesce(profile.first_name, '') || ' ' ||
           coalesce(profile.last_name, '')) as actor_name,
         (select item->>'label' from jsonb_array_elements(
            settlement.effective_snapshot->'lessonSettlementTypes') item
          where item->>'stableKey' = entries.decision->>'settlementTypeKey' limit 1)
           as settlement_type_label,
         (select item->>'label' from jsonb_array_elements(
            compensation.effective_snapshot->'teacherCompensationRules') item
          where item->>'stableKey' = entries.decision->>'teacherCompensationRuleKey' limit 1)
           as teacher_compensation_rule_label
       from entries
       left join app.profiles profile
         on profile.user_id = entries.actor_user_id and profile.deleted_at is null
       left join app.crm_configuration_revisions settlement
         on settlement.id = entries.settlement_revision_id
       left join app.crm_configuration_revisions compensation
         on compensation.id = entries.compensation_revision_id
       order by entries.created_at desc, entries.kind desc, entries.version desc`,
      [lessonId],
    );
    return {
      lessonId,
      items: history.rows.map((row) => {
        const { teacherRateSnapshot: _rate, ...decision } = row.decision;
        if (!lesson.rows[0]!.can_read_teacher_compensation) {
          delete decision.teacherCompensationValueMinor;
        }
        return {
          kind: row.kind,
          version: Number(row.version),
          decision,
          settlementTypeLabel: row.settlement_type_label,
          teacherCompensationRuleLabel: row.teacher_compensation_rule_label,
          reason: row.reason_text,
          actorUserId: row.actor_user_id,
          actorName: row.actor_name || (row.worker_id ? "Автоматический расчёт" : "Сотрудник"),
          createdAt: new Date(row.created_at).toISOString(),
          effective: row.effective,
        };
      }),
    };
  }

  async preview(
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettlementCorrectionPreviewDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const preview = await this.database.transaction(async (client) => {
      await client.query("savepoint lesson_settlement_correction_preview");
      try {
        return await this.applyCorrection(
          client,
          actor,
          lessonId,
          dto,
          randomUUID(),
          false,
        );
      } finally {
        await client.query(
          "rollback to savepoint lesson_settlement_correction_preview",
        );
        await client.query(
          "release savepoint lesson_settlement_correction_preview",
        );
      }
    });
    const correctionFingerprint = this.fingerprint(dto, preview);
    const signed = this.previewTokens.issueLessonTransition({
      kind: "lesson.transition",
      operation: "correct",
      actorUserId: actor.userId,
      lessonId,
      expectedVersion: dto.expectedVersion,
      transitionFingerprint: correctionFingerprint,
    });
    return {
      canConfirm: true,
      financialPreview: this.financialProjection(preview.settled),
      resourceChanges: preview.resourceChange,
      previewToken: signed.token,
      previewExpiresAt: signed.expiresAt,
    };
  }

  async commit(
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettlementCorrectionCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    const signed = this.previewTokens.verifyLessonTransition(dto.previewToken);
    if (
      signed.operation !== "correct" ||
      signed.actorUserId !== actor.userId ||
      signed.lessonId !== lessonId ||
      signed.expectedVersion !== dto.expectedVersion
    ) {
      throw new UnprocessableEntityException({
        code: "LESSON_SETTLEMENT_CORRECTION_PREVIEW_INVALID",
      });
    }
    const correctionId = this.stableCorrectionId(
      actor.userId,
      lessonId,
      metadata.idempotencyKey,
    );
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      authorization:
        this.policy.teacherCompensationMutationAuthorization(actor),
      operation: "schedule.lesson.settlement-correction",
      idempotencyKey: metadata.idempotencyKey,
      payload: { lessonId, ...dto },
      aggregateType: "schedule:lesson",
      aggregateId: lessonId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      audit: {
        action: "crm.lesson_settlement_corrected",
        entityType: "lesson",
        entityId: lessonId,
        reason: "lesson.settlement.correction",
        reasonText: dto.reasonText.trim(),
        beforeRef: { lessonId, version: dto.expectedVersion },
      },
      outbox: {
        type: "schedule.lesson.changed",
        payload: { lessonId, action: "settlement-corrected" },
      },
      mutate: async (client, nextVersion) => {
        const applied = await this.applyCorrection(
          client,
          actor,
          lessonId,
          dto,
          correctionId,
          true,
        );
        if (
          this.fingerprint(dto, applied) !==
          signed.transitionFingerprint
        ) {
          throw new UnprocessableEntityException({
            code: "LESSON_SETTLEMENT_CORRECTION_PREVIEW_STALE",
          });
        }
        const updated = applied.resourceChange
          ? await client.query<{ version: number | string }>(
              "select version from app.lessons where id = $1", [lessonId],
            )
          : await client.query<{ version: number | string }>(
              `update app.lessons set updated_at = now()
               where id = $1 and version = $2
                 and lifecycle_state = 'successfully_completed'
               returning version`,
              [lessonId, dto.expectedVersion],
            );
        if (
          !updated.rows[0] ||
          Number(updated.rows[0].version) !== nextVersion
        ) {
          throw new ConflictException({ code: "LESSON_VERSION_DIVERGED" });
        }
        return {
          lessonId,
          correctionId,
          correctionVersion: applied.correctionVersion,
          resourceChanges: applied.resourceChange,
          clientFinancialFactIds: applied.settled.clientFacts.map(
            (fact) => fact.id,
          ),
          teacherFinancialFactId: applied.settled.teacherFact.id,
        };
      },
    });
    if (!mutation.replayed) {
      await this.reservations.publishLessonSettlementPostCommit(lessonId);
    }
    return {
      ...mutation.resultRef,
      version: mutation.version,
      replayed: mutation.replayed,
    };
  }

  private async applyCorrection(
    client: PoolClient,
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettlementCorrectionPreviewDto,
    correctionId: string,
    lock: boolean,
  ) {
    const lesson = await client.query<{
      version: number | string;
      lifecycle_state: string;
      branch_id: string;
      duration_minutes: number;
    }>(
      `select version, lifecycle_state, branch_id, duration_minutes from app.lessons
       where id = $1 and deleted_at is null
       ${lock ? "for update" : ""}`,
      [lessonId],
    );
    const source = lesson.rows[0];
    if (!source) throw new NotFoundException("Урок не найден.");
    if (Number(source.version) !== dto.expectedVersion) {
      throw new ConflictException({ code: "STALE_AGGREGATE_VERSION" });
    }
    if (source.lifecycle_state !== "successfully_completed") {
      throw new ConflictException({
        code: "LESSON_SETTLEMENT_CORRECTION_NOT_ALLOWED",
      });
    }
    const resources = await applyLessonResourceEdit(
      client, actor, lessonId, dto.resources, this.constraints,
    );
    const storedTeacherDecision = this.policy.canManageTeacherCompensation(actor)
      ? undefined
      : await this.settlement.reuseStoredTeacherCompensation(
          client,
          lessonId,
          dto.financialDecision,
        );
    const decision = await this.settlement.resolvePlannedDecision(client, {
      branchId: resources.branchId,
      durationMinutes: source.duration_minutes,
      decision: {
        ...dto.financialDecision,
        teacherRateSnapshot: resources.teacherRateSnapshot,
      },
      actorUserId: actor.userId,
      authorization:
        this.policy.teacherCompensationMutationAuthorization(actor),
      reasonText: dto.reasonText,
      ...(storedTeacherDecision
        ? {
            preservedTeacherDecision: {
              teacherCompensationRuleKey:
                storedTeacherDecision.teacherCompensationRuleKey,
              teacherCompensationValueMinor:
                storedTeacherDecision.teacherCompensationValueMinor,
              teacherCreditedDurationMinutes:
                storedTeacherDecision.teacherCreditedDurationMinutes,
              teacherCompensationSource:
                storedTeacherDecision.teacherCompensationSource,
            },
          }
        : {}),
    });
    const prepared = await this.settlement.preparePlan(
      client,
      resources.branchId,
      decision,
      actor.userId,
    );
    const previous = await client.query<{
      id: string;
      version: number | string;
    }>(
      `select id, version from app.lesson_settlement_corrections
       where lesson_id = $1 order by version desc limit 1
       ${lock ? "for update" : ""}`,
      [lessonId],
    );
    const correctionVersion = Number(previous.rows[0]?.version ?? 0) + 1;
    await client.query(
      `insert into app.lesson_settlement_corrections (
         id, lesson_id, version, supersedes_correction_id, decision,
         settlement_revision_id, compensation_revision_id,
         reason_text, actor_user_id
       ) values ($1,$2,$3,$4,$5::jsonb,$6,$7,$8,$9)`,
      [
        correctionId,
        lessonId,
        correctionVersion,
        previous.rows[0]?.id ?? null,
        JSON.stringify(decision),
        prepared.settlementRevisionId,
        prepared.compensationRevisionId,
        dto.reasonText.trim(),
        actor.userId,
      ],
    );
    const settled = await this.settlement.settle(client, lessonId, {
      context: "settle",
      decision,
      reasonText: dto.reasonText.trim(),
      configurationRevisionIds: {
        settlementRevisionId: prepared.settlementRevisionId,
        compensationRevisionId: prepared.compensationRevisionId,
      },
      correction: { id: correctionId },
    });
    return { correctionVersion, settled, decision, resourceChange: resources.change };
  }

  private fingerprint(
    dto: LessonSettlementCorrectionPreviewDto,
    applied: Awaited<ReturnType<LessonSettlementCorrectionService["applyCorrection"]>>,
  ) {
    return fingerprintPayload({
      expectedVersion: dto.expectedVersion,
      reasonText: dto.reasonText.trim(),
      financialDecision: applied.decision,
      resourceChanges: applied.resourceChange,
      financial: this.financialProjection(applied.settled),
    });
  }

  private financialProjection(settled: LessonSettlementResult) {
    return {
      clientFacts: settled.clientFacts.map((fact) => ({
        clientId: fact.clientId,
        settlementTypeKey: fact.settlementTypeKey,
        settlementLabel: fact.settlementLabel,
        chargeType: fact.chargeType,
        subscriptionId: fact.subscriptionId,
        payerStudentId: fact.payerStudentId ?? null,
        pricingSnapshot: fact.pricingSnapshot ?? null,
        amountMinor: fact.amountMinor,
        units: fact.units,
      })),
      teacherFact: {
        teacherId: settled.teacherFact.teacherId,
        compensationRuleKey: settled.teacherFact.compensationRuleKey,
        compensationRuleLabel: settled.teacherFact.compensationRuleLabel,
        amountMinor: settled.teacherFact.amountMinor,
      },
    };
  }

  private assertMetadata(metadata: LessonCommandMetadata) {
    if (
      !/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey) ||
      !metadata.requestId ||
      metadata.requestId.length > 160
    ) {
      throw new UnprocessableEntityException({
        code: "MUTATION_METADATA_REQUIRED",
      });
    }
  }

  private stableCorrectionId(userId: string, lessonId: string, key: string) {
    const bytes = createHash("sha256")
      .update(`schedule.lesson.correction\0${userId}\0${lessonId}\0${key}`)
      .digest()
      .subarray(0, 16);
    bytes[6] = (bytes[6]! & 0x0f) | 0x50;
    bytes[8] = (bytes[8]! & 0x3f) | 0x80;
    const hex = bytes.toString("hex");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }
}
