import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { attachStudentToLead } from "./lead-student-link";
import { CrmPolicy } from "./crm.policy";
import { DuplicateCandidatesQuery } from "./dto/duplicate-candidates.query";
import { DuplicateDecisionDto } from "./dto/duplicate-decision.dto";

interface DuplicateCandidateRow {
  id: string;
  entity_type_a: string;
  entity_id_a: string;
  entity_type_b: string;
  entity_id_b: string;
  match_type: string;
  match_value: string;
  confidence: string | number;
  source: string;
  status: string;
  decided_at: Date | string | null;
  decided_by: string | null;
  decision_notes: string | null;
  created_at: Date | string;
  updated_at: Date | string;
  entity_a_name: string | null;
  entity_b_name: string | null;
  entity_a_phone: string | null;
  entity_b_phone: string | null;
  entity_a_email: string | null;
  entity_b_email: string | null;
}

/**
 * Duplicate-candidate review queue (app.duplicate_candidates): list pending
 * lead/student duplicate pairs and decide them (dismiss or attach a student to
 * its matched lead). Extracted from CrmService (B5) — self-contained.
 */
@Injectable()
export class DuplicatesService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly audit: AuditService,
  ) {}

  async listDuplicateCandidates(
    actor: ActorContext,
    query: DuplicateCandidatesQuery,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<DuplicateCandidateRow>(
      `
        select dc.id, dc.entity_type_a, dc.entity_id_a, dc.entity_type_b, dc.entity_id_b,
          dc.match_type, dc.match_value, dc.confidence, dc.source, dc.status,
          dc.decided_at, dc.decided_by, dc.decision_notes, dc.created_at, dc.updated_at,
          coalesce(
            nullif(concat_ws(' ', spa.first_name, spa.last_name), ''),
            nullif(concat_ws(' ', la.first_name, la.last_name), '')
          ) as entity_a_name,
          coalesce(
            nullif(concat_ws(' ', spb.first_name, spb.last_name), ''),
            nullif(concat_ws(' ', lb.first_name, lb.last_name), '')
          ) as entity_b_name,
          coalesce(spa.phone, la.phone) as entity_a_phone,
          coalesce(spb.phone, lb.phone) as entity_b_phone,
          coalesce(ua.email, la.email) as entity_a_email,
          coalesce(ub.email, lb.email) as entity_b_email
        from app.duplicate_candidates dc
        left join app.students sa on dc.entity_type_a = 'student' and sa.id = dc.entity_id_a and sa.deleted_at is null
        left join app.profiles spa on spa.id = sa.profile_id and spa.deleted_at is null
        left join app.users ua on ua.id = spa.user_id and ua.deleted_at is null
        left join app.leads la on dc.entity_type_a = 'lead' and la.id = dc.entity_id_a and la.deleted_at is null
        left join app.students sb on dc.entity_type_b = 'student' and sb.id = dc.entity_id_b and sb.deleted_at is null
        left join app.profiles spb on spb.id = sb.profile_id and spb.deleted_at is null
        left join app.users ub on ub.id = spb.user_id and ub.deleted_at is null
        left join app.leads lb on dc.entity_type_b = 'lead' and lb.id = dc.entity_id_b and lb.deleted_at is null
        where dc.deleted_at is null
          and ($1::text is null or dc.status = $1)
          and (
            $2::uuid is null
            or (dc.entity_type_a = 'lead' and dc.entity_id_a = $2)
            or (dc.entity_type_b = 'lead' and dc.entity_id_b = $2)
          )
        order by dc.created_at desc, dc.id desc
        limit $3
      `,
      [query.status ?? "pending", query.leadId ?? null, limit],
    );
    return {
      items: result.rows.map((row) => this.toDuplicateCandidateDto(row)),
    };
  }

  async decideDuplicateCandidate(
    actor: ActorContext,
    candidateId: string,
    dto: DuplicateDecisionDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const candidateResult = await this.database.query<DuplicateCandidateRow>(
      `
        select dc.id, dc.entity_type_a, dc.entity_id_a, dc.entity_type_b, dc.entity_id_b,
          dc.match_type, dc.match_value, dc.confidence, dc.source, dc.status,
          dc.decided_at, dc.decided_by, dc.decision_notes, dc.created_at, dc.updated_at,
          null::text as entity_a_name, null::text as entity_b_name,
          null::text as entity_a_phone, null::text as entity_b_phone,
          null::text as entity_a_email, null::text as entity_b_email
        from app.duplicate_candidates dc
        where dc.id = $1 and dc.deleted_at is null
        limit 1
      `,
      [candidateId],
    );
    const candidate = candidateResult.rows[0];
    if (!candidate) throw new NotFoundException("Кандидат дубля не найден.");

    if (dto.status === "attached") {
      await this.attachDuplicateCandidate(candidate);
    }

    const updated = await this.database.query<DuplicateCandidateRow>(
      `
        update app.duplicate_candidates
        set status = $2,
          decided_at = now(),
          decided_by = $3,
          decision_notes = $4,
          updated_at = now()
        where id = $1 and deleted_at is null
        returning id, entity_type_a, entity_id_a, entity_type_b, entity_id_b,
          match_type, match_value, confidence, source, status, decided_at,
          decided_by, decision_notes, created_at, updated_at,
          null::text as entity_a_name, null::text as entity_b_name,
          null::text as entity_a_phone, null::text as entity_b_phone,
          null::text as entity_a_email, null::text as entity_b_email
      `,
      [candidateId, dto.status, actor.userId, dto.notes?.trim() || null],
    );
    const row = updated.rows[0];
    await this.audit.record({
      actor,
      action: "crm.duplicate_candidate_decided",
      entityType: "student",
      entityId: candidateId,
      metadata: {
        status: dto.status,
        entityTypeA: candidate.entity_type_a,
        entityTypeB: candidate.entity_type_b,
      },
    });
    return this.toDuplicateCandidateDto(row);
  }

  private async attachDuplicateCandidate(candidate: DuplicateCandidateRow) {
    const leadId =
      candidate.entity_type_a === "lead"
        ? candidate.entity_id_a
        : candidate.entity_type_b === "lead"
          ? candidate.entity_id_b
          : null;
    const studentId =
      candidate.entity_type_a === "student"
        ? candidate.entity_id_a
        : candidate.entity_type_b === "student"
          ? candidate.entity_id_b
          : null;
    if (!leadId || !studentId) {
      throw new BadRequestException("Прикрепить можно только пару лид-ученик.");
    }
    // Общий с ручным «Прикрепить к ученику» — см. lead-student-link.ts.
    await attachStudentToLead(this.database, studentId, leadId);
  }

  private toDuplicateCandidateDto(row: DuplicateCandidateRow) {
    return {
      id: row.id,
      entityTypeA: row.entity_type_a,
      entityIdA: row.entity_id_a,
      entityTypeB: row.entity_type_b,
      entityIdB: row.entity_id_b,
      matchType: row.match_type,
      matchValue: row.match_value,
      confidence: Number(row.confidence),
      source: row.source,
      status: row.status,
      decidedAt: row.decided_at,
      decidedBy: row.decided_by,
      decisionNotes: row.decision_notes,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      entityA: {
        name: row.entity_a_name,
        phone: row.entity_a_phone,
        email: row.entity_a_email,
      },
      entityB: {
        name: row.entity_b_name,
        phone: row.entity_b_phone,
        email: row.entity_b_email,
      },
    };
  }
}
