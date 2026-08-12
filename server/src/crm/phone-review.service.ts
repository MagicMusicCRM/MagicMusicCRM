import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
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

  async countPhoneReviewQueue(actor: ActorContext): Promise<{ count: number }> {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{ count: string }>(
      `select count(*)::text as count from app.phone_review_queue where resolved_at is null`,
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
         from app.phone_review_queue
        where resolved_at is null
        order by created_at desc
        limit $1`,
      [capped],
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
          select id, entity_type, entity_id
          from app.phone_review_queue
          where id = $1 and resolved_at is null
          limit 1
          for update
        `,
        [id],
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
                  set phone = $2, phone_normalized = $2, updated_at = now()
                  where id = $1 and deleted_at is null
                  returning id
                `,
                [current.entity_id, resolvedPhone],
              )
            : await client.query(
                `
                  update app.profiles
                  set phone = $2, phone_normalized = $2, updated_at = now()
                  where id = $1 and deleted_at is null
                  returning id
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
