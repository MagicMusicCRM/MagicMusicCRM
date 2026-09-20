import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import {
  branchIdExpr,
  currentActorRoleSql,
  managerBranchScopeSql,
} from "./branch-scope";
import { CrmPolicy } from "./crm.policy";
import {
  PhoneReviewResolutionAction,
  ResolvePhoneReviewDto,
} from "./dto/resolve-phone-review.dto";
import { normalizePhoneRu } from "./phone.util";

/**
 * Phone-review queue (app.phone_review_queue): unresolved entries flagged when
 * an imported/entered phone could not be normalized. Staff can either correct
 * the source entity through the canonical RU normalizer or accept the value
 * as-is with an accountable resolution note.
 * Extracted from CrmService (B5) — self-contained (database + policy).
 */
@Injectable()
export class PhoneReviewService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly audit: AuditService,
  ) {}

  private actorScopeSql(queueAlias: string, actorExpression: string): string {
    const role = currentActorRoleSql(actorExpression);
    return `(
      ${role}::text <> all(array['admin', 'manager']::text[])
      or (
        ${queueAlias}.entity_type = 'lead'
        and exists (
          select 1 from app.leads scoped_lead
          where scoped_lead.id = ${queueAlias}.entity_id
            and scoped_lead.deleted_at is null
            and ${managerBranchScopeSql({
              roleExpression: role,
              userIdExpression: actorExpression,
              branchExpression: branchIdExpr("scoped_lead"),
            })}
        )
      )
      or (
        ${queueAlias}.entity_type = 'profile'
        and exists (
          select 1 from app.students scoped_student
          where scoped_student.profile_id = ${queueAlias}.entity_id
            and scoped_student.deleted_at is null
            and ${managerBranchScopeSql({
              roleExpression: role,
              userIdExpression: actorExpression,
              branchExpression: branchIdExpr("scoped_student"),
            })}
        )
      )
    )`;
  }

  async countPhoneReviewQueue(actor: ActorContext): Promise<{ count: number }> {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{ count: string }>(
      `select count(*)::text as count
         from app.phone_review_queue review
        where review.resolved_at is null
          and ${this.actorScopeSql("review", "$1")}`,
      [actor.userId],
    );
    return { count: Number(result.rows[0]?.count ?? 0) };
  }

  async listPhoneReviewQueue(actor: ActorContext, limit = 50) {
    this.policy.assertCanReadOperationalData(actor);
    const capped = Math.min(Math.max(limit, 1), 200);
    const result = await this.database.query<{
      id: string;
      entity_type: string;
      entity_id: string;
      raw_phone: string | null;
      reason: string;
      created_at: string;
    }>(
      `select id, entity_type, entity_id, raw_phone, reason, created_at
         from app.phone_review_queue review
        where review.resolved_at is null
          and ${this.actorScopeSql("review", "$1")}
        order by created_at desc
        limit $2`,
      [actor.userId, capped],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        entityType: row.entity_type,
        entityId: row.entity_id,
        rawPhone: row.raw_phone,
        reason: row.reason,
        createdAt: row.created_at,
      })),
    };
  }

  async resolvePhoneReview(
    actor: ActorContext,
    id: string,
    dto: ResolvePhoneReviewDto,
  ) {
    this.policy.assertCanWriteCrm(actor);

    const note = dto.resolutionNote?.trim();
    if (!note) {
      throw new BadRequestException("Укажите причину решения.");
    }

    let resolvedPhone: string | null = null;
    if (dto.action === "corrected") {
      const normalized = normalizePhoneRu(dto.phone);
      if (!normalized.canonical) {
        throw new BadRequestException(
          "Исправленный номер должен быть корректным российским номером.",
        );
      }
      resolvedPhone = normalized.canonical;
    }

    const resolved = await this.database.transaction(async (client) => {
      const currentResult = await client.query<{
        id: string;
        entity_type: "lead" | "profile";
        entity_id: string;
      }>(
        `
          select review.id, review.entity_type, review.entity_id
          from app.phone_review_queue review
          where review.id = $1 and review.resolved_at is null
            and ${this.actorScopeSql("review", "$2")}
          limit 1
          for update of review
        `,
        [id, actor.userId],
      );
      const current = currentResult.rows[0];
      if (!current) {
        throw new NotFoundException(
          "Запись проверки телефона не найдена или уже разобрана.",
        );
      }

      if (dto.action === "corrected") {
        const target =
          current.entity_type === "lead"
            ? await client.query(
                `
                  update app.leads
                  set phone = $2,
                      phone_normalized = $2,
                      version = version + 1,
                      updated_at = now()
                  where id = $1 and deleted_at is null
                  returning id
                `,
                [current.entity_id, resolvedPhone],
              )
            : await client.query(
                `
                  with updated_profile as (
                    update app.profiles
                    set phone = $2, phone_normalized = $2, updated_at = now()
                    where id = $1 and deleted_at is null
                    returning id
                  ), updated_students as (
                    update app.students student
                    set version = student.version + 1,
                        updated_at = now()
                    from updated_profile profile
                    where student.profile_id = profile.id
                      and student.deleted_at is null
                    returning student.id
                  )
                  select id from updated_profile
                `,
                [current.entity_id, resolvedPhone],
              );
        if (target.rowCount !== 1) {
          throw new NotFoundException(
            "Связанная карточка не найдена или уже удалена.",
          );
        }
      }

      const updated = await client.query<{
        id: string;
        entity_type: "lead" | "profile";
        entity_id: string;
        resolution_action: PhoneReviewResolutionAction;
        resolution_note: string;
        resolved_phone: string | null;
        resolved_at: string;
      }>(
        `
          update app.phone_review_queue
          set resolved_at = now(),
              resolved_by = $2,
              resolution_action = $3,
              resolution_note = $4,
              resolved_phone = $5
          where id = $1 and resolved_at is null
          returning id, entity_type, entity_id, resolution_action,
            resolution_note, resolved_phone, resolved_at
        `,
        [id, actor.userId, dto.action, note, resolvedPhone],
      );
      return updated.rows[0];
    });

    await this.audit.record({
      actor,
      action: "crm.phone_review_resolved",
      entityType: "phone_review_queue",
      entityId: resolved.id,
      metadata: {
        action: resolved.resolution_action,
        entityType: resolved.entity_type,
        entityId: resolved.entity_id,
        reason: resolved.resolution_note,
      },
    });

    return {
      id: resolved.id,
      action: resolved.resolution_action,
      resolvedPhone: resolved.resolved_phone,
      resolvedAt: resolved.resolved_at,
    };
  }
}
