import {
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from "@nestjs/common";
import type { QueryResult, QueryResultRow } from "pg";
import { AuditService } from "../audit/audit.service";
import { LeadIntakePort } from "../common/lead-intake.port";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { normalizePhoneRu, normalizedPhoneExpr } from "./phone.util";
import { mergeAndAssignStudentProfile } from "./student-profile-link";

interface LeadIntakeQueryExecutor {
  query<T extends QueryResultRow = QueryResultRow>(
    query: string,
    params?: unknown[],
  ): Promise<QueryResult<T>>;
}

interface AutomaticIntakeProfile {
  profile_id: string; first_name: string | null;
  last_name: string | null; phone: string | null;
}

type AutomaticIntakeEntityOutcome = {
  kind: "lead" | "student"; id: string;
  created: boolean; linked: boolean;
};

type AutomaticIntakeOutcome =
  | AutomaticIntakeEntityOutcome | { kind: "review" } | { kind: "no_profile" };

/**
 * Inbound lead capture: promote a chat sender or public-site submission into a
 * lead, and resolve chat users <-> CRM contacts. This is the LeadIntakePort
 * implementation (messenger depends on it via LEAD_INTAKE_PORT). Distinct from
 * the lead pipeline (board/card/CRUD) in LeadsService — it only inserts leads
 * and user_crm_links, never reads the funnel.
 */
@Injectable()
export class LeadIntakeService implements LeadIntakePort {
  private readonly logger = new Logger(LeadIntakeService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
  ) {}

  async resolveLeadChatUser(actor: ActorContext, leadId: string) {
    this.policy.assertCanWriteCrm(actor);
    const lead = await this.database.query<{
      id: string;
      name: string;
      phone: string | null;
    }>(
      `
        select id,
          coalesce(
            nullif(btrim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), ''),
            'Лид'
          ) as name,
          phone
        from app.leads
        where id = $1 and deleted_at is null
        limit 1
      `,
      [leadId],
    );
    if (!lead.rows[0]) throw new NotFoundException("Лид не найден.");

    const link = await this.database.query<{ user_id: string }>(
      `
        select user_id
        from app.user_crm_links
        where entity_type = 'lead' and entity_id = $1 and deleted_at is null
        order by confirmed_at desc nulls last, created_at desc
        limit 1
      `,
      [leadId],
    );
    if (link.rows[0]) {
      return { userId: link.rows[0].user_id, name: lead.rows[0].name };
    }

    const phone = this.normalizeContactPhone(lead.rows[0].phone);
    if (phone) {
      const byPhone = await this.database.query<{ user_id: string }>(
        `
          select min(candidate.user_id::text)::uuid as user_id
          from (
            select distinct p.user_id
            from app.profiles p
            join app.users u on u.id = p.user_id and u.deleted_at is null
            where p.deleted_at is null
              and ${normalizedPhoneExpr("p.phone")} = $1
              and u.role = 'client'
          ) candidate
          having count(*) = 1
        `,
        [phone],
      );
      if (byPhone.rows[0]) {
        return { userId: byPhone.rows[0].user_id, name: lead.rows[0].name };
      }
    }
    return { userId: null, name: lead.rows[0].name };
  }

  // Reverse lookup: given a messenger user (a chat partner), find the CRM
  // lead/student they map to so staff can open the right card from a chat.
  async resolveContactForUser(actor: ActorContext, userId: string) {
    this.policy.assertCanWriteCrm(actor);
    const links = await this.database.query<{
      entity_type: string;
      entity_id: string;
    }>(
      `
        select link.entity_type, link.entity_id
        from app.user_crm_links link
        left join app.leads lead
          on link.entity_type = 'lead'
         and lead.id = link.entity_id
         and lead.deleted_at is null
        left join app.students student
          on link.entity_type = 'student'
         and student.id = link.entity_id
         and student.deleted_at is null
        where link.user_id = $1 and link.deleted_at is null
          and (
            (link.entity_type = 'lead' and lead.id is not null)
            or (link.entity_type = 'student' and student.id is not null)
          )
      `,
      [userId],
    );
    let studentId: string | null = null;
    let leadId: string | null = null;
    for (const row of links.rows) {
      if (row.entity_type === "student") studentId ??= row.entity_id;
      if (row.entity_type === "lead") leadId ??= row.entity_id;
    }
    // Students created in-app own their user directly (their profile.user_id),
    // which may not have an explicit crm-link row.
    if (!studentId) {
      const owned = await this.database.query<{ id: string }>(
        `
          select s.id
          from app.students s
          join app.profiles p on p.id = s.profile_id and p.deleted_at is null
          where p.user_id = $1 and s.deleted_at is null
          order by s.created_at desc
          limit 1
        `,
        [userId],
      );
      studentId = owned.rows[0]?.id ?? null;
    }
    // Conversion path (правки №2): createStudent mints a NEW profile for the
    // student, so neither of the two checks above sees it. Resolve via
    // students.lead_id ← the user's linked lead, so «Открыть карточку» opens
    // the student card, not the stale lead, after conversion.
    if (!studentId && leadId) {
      const converted = await this.database.query<{ id: string }>(
        `
          select s.id
          from app.students s
          where s.lead_id = $1 and s.deleted_at is null
          order by s.created_at desc
          limit 1
        `,
        [leadId],
      );
      studentId = converted.rows[0]?.id ?? null;
    }
    return { studentId, leadId };
  }

  async saveContactFromChat(
    actor: ActorContext,
    dto: { userId: string; as: "lead" | "student" },
  ) {
    this.policy.assertCanWriteCrm(actor);
    type SaveOutcome =
      | {
          kind: "lead";
          id: string;
          created: boolean;
          userId: string;
          linked?: boolean;
        }
      | {
          kind: "student";
          id: string;
          created: boolean;
          userId: string;
          linked?: boolean;
        };

    // Manual save and automatic chat intake use the same per-user key. Every
    // dedupe check and both entity/link inserts therefore happen after one
    // serializing lock and inside one transaction.
    const outcome = await this.database.transaction<SaveOutcome>(async (client) => {
      await client.query(
        "select pg_advisory_xact_lock(hashtext($1))",
        [`lead-intake:${dto.userId.toLowerCase()}`],
      );

      const profileResult = await client.query<{
        profile_id: string;
        user_id: string;
        first_name: string | null;
        last_name: string | null;
        phone: string | null;
      }>(
        `select p.id as profile_id, p.user_id, p.first_name, p.last_name, p.phone
         from app.profiles p
         join app.users u on u.id = p.user_id
          and u.deleted_at is null and u.role = 'client'
         where p.user_id = $1 and p.deleted_at is null
         limit 1`,
        [dto.userId],
      );
      const profile = profileResult.rows[0];
      if (!profile) throw new NotFoundException("Пользователь чата не найден.");

      const firstName = (profile.first_name ?? "").trim() || "Без имени";
      const lastName = (profile.last_name ?? "").trim() || null;
      const phone = (profile.phone ?? "").trim() || null;
      const matchedPhone = this.normalizeContactPhone(phone);

      if (dto.as === "lead") {
        const existingStudent = await this.findStudentForUser(
          profile.user_id,
          profile.profile_id,
          client as unknown as LeadIntakeQueryExecutor,
        );
        if (existingStudent) {
          return {
            kind: "student",
            id: existingStudent,
            created: false,
            userId: profile.user_id,
          };
        }

        const existing = await client.query<{ entity_id: string }>(
          `select link.entity_id from app.user_crm_links link
           join app.leads lead on lead.id = link.entity_id and lead.deleted_at is null
           where link.user_id = $1 and link.entity_type = 'lead'
             and link.deleted_at is null
           order by link.confirmed_at desc nulls last, link.created_at desc
           limit 1`,
          [profile.user_id],
        );
        if (existing.rows[0]) {
          return {
            kind: "lead",
            id: existing.rows[0].entity_id,
            created: false,
            userId: profile.user_id,
          };
        }

        if (matchedPhone) {
          // Different chat users can share a family phone. Serialize that
          // dedupe key too, then consider only an unowned/same-user lead.
          await client.query(
            "select pg_advisory_xact_lock(hashtext($1))",
            [`lead-phone:${matchedPhone}`],
          );
          const byPhone = await client.query<{ id: string }>(
            `with candidates as (
               select distinct l.id
               from app.leads l
               where l.deleted_at is null
                 and ${normalizedPhoneExpr("l.phone")} = $1
                 and not exists (
                   select 1 from app.user_crm_links owner_link
                   where owner_link.entity_type = 'lead'
                     and owner_link.entity_id = l.id
                     and owner_link.deleted_at is null
                     and owner_link.user_id <> $2
                 )
             )
             select min(id::text)::uuid as id
             from candidates
             having count(*) = 1`,
            [matchedPhone, profile.user_id],
          );
          const phoneLeadId = byPhone.rows[0]?.id;
          if (phoneLeadId) {
            const linked = await client.query<{ entity_id: string }>(
              `insert into app.user_crm_links
                 (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
               values ($1, 'lead', $2, $3, 'manual_phone', $4, now())
               on conflict (entity_type, entity_id) where deleted_at is null
               do nothing
               returning entity_id`,
              [profile.user_id, phoneLeadId, matchedPhone, actor.userId],
            );
            if (linked.rows[0]) {
              return {
                kind: "lead",
                id: phoneLeadId,
                created: false,
                userId: profile.user_id,
                linked: true,
              };
            }
            const owner = await client.query<{ user_id: string }>(
              `select user_id from app.user_crm_links
               where entity_type = 'lead' and entity_id = $1
                 and deleted_at is null
               limit 1`,
              [phoneLeadId],
            );
            if (owner.rows[0]?.user_id === profile.user_id) {
              return {
                kind: "lead",
                id: phoneLeadId,
                created: false,
                userId: profile.user_id,
              };
            }
            // The candidate was claimed by somebody else. Never return that
            // person's card; continue below and create an isolated lead.
          }
        }

        const statusRow = await client.query<{ id: string }>(
          `select id
           from app.lead_statuses
           where stage_key = 'new'
              or lower(btrim(name)) in ('новый', 'новые')
           order by (stage_key = 'new') desc, sort_order, id
           limit 1`,
        );
        const inserted = await client.query<{ id: string }>(
          `insert into app.leads
             (first_name, last_name, phone, source, source_id, status_id, created_by)
           select $1, $2, $3, source.display_name, source.id, $4, $5
           from app.lead_sources source
           where lower(btrim(source.canonical_name)) = 'app'
             and source.is_active
             and source.deleted_at is null
           limit 1
           returning id`,
          [
            firstName,
            lastName,
            phone,
            statusRow.rows[0]?.id ?? null,
            actor.userId,
          ],
        );
        const leadId = inserted.rows[0].id;
        await client.query(
          `insert into app.user_crm_links
             (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
           values ($1, 'lead', $2, $3, 'manual_phone', $4, now())`,
          [profile.user_id, leadId, matchedPhone, actor.userId],
        );
        return {
          kind: "lead",
          id: leadId,
          created: true,
          userId: profile.user_id,
        };
      }

      const existingStudentId = await this.findStudentForUser(
        profile.user_id,
        profile.profile_id,
        client as unknown as LeadIntakeQueryExecutor,
      );
      if (existingStudentId) {
        return {
          kind: "student",
          id: existingStudentId,
          created: false,
          userId: profile.user_id,
        };
      }
      const leadLink = await client.query<{ entity_id: string }>(
        `select link.entity_id from app.user_crm_links link
         join app.leads lead on lead.id = link.entity_id and lead.deleted_at is null
         where link.user_id = $1 and link.entity_type = 'lead'
           and link.deleted_at is null
         order by link.confirmed_at desc nulls last, link.created_at desc
         limit 1`,
        [profile.user_id],
      );
      const linkedLeadId = leadLink.rows[0]?.entity_id ?? null;
      if (linkedLeadId) {
        // This is the exact same lock used by CrmService.createStudent.
        // Manual chat promotion and lead-card conversion therefore cannot
        // create two active students for one lead when they race.
        await client.query(
          "select pg_advisory_xact_lock(hashtextextended($1::uuid::text, 0))",
          [linkedLeadId],
        );
        const converted = await client.query<{ id: string }>(
          `select id from app.students
           where lead_id = $1 and deleted_at is null
           limit 1`,
          [linkedLeadId],
        );
        if (converted.rows[0]) {
          return {
            kind: "student",
            id: converted.rows[0].id,
            created: false,
            userId: profile.user_id,
          };
        }
      }
      const inserted = await client.query<{ id: string }>(
        `insert into app.students (profile_id, status, lead_id, source_id)
         values (
           $1,
           'active',
           $2,
           coalesce(
             (
               select lead.source_id
               from app.leads lead
               where lead.id = $2
                 and lead.deleted_at is null
             ),
             (
               select source.id
               from app.lead_sources source
               where lower(btrim(source.canonical_name)) = 'app'
                 and source.is_active
                 and source.deleted_at is null
               limit 1
             )
           )
         )
         returning id`,
        [profile.profile_id, linkedLeadId],
      );
      const studentId = inserted.rows[0].id;
      await client.query(
        `insert into app.user_crm_links
           (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
         values ($1, 'student', $2, $3, 'manual_phone', $4, now())`,
        [profile.user_id, studentId, matchedPhone, actor.userId],
      );
      return {
        kind: "student",
        id: studentId,
        created: true,
        userId: profile.user_id,
      };
    });

    if (outcome.created) {
      try {
        await this.audit.record({
          actor,
          action:
            outcome.kind === "lead" ? "crm.lead_created" : "crm.student_created",
          entityType: outcome.kind,
          entityId: outcome.id,
          metadata: { fromChat: true, userId: outcome.userId },
        });
      } catch (error) {
        this.logger.error(
          `Audit write failed for chat-created ${outcome.kind} ${outcome.id}: ${String(error)}`,
        );
      }
    } else if (outcome.linked) {
      try {
        await this.audit.record({
          actor,
          action: "crm.client_user_linked",
          entityType: outcome.kind,
          entityId: outcome.id,
          metadata: { fromChat: true, userId: outcome.userId },
        });
      } catch (error) {
        this.logger.error(
          `Audit write failed for chat link ${outcome.kind}/${outcome.id}: ${String(error)}`,
        );
      }
    }
    if (outcome.created || outcome.linked) {
      this.realtime.emitCrmChanged({
        entity: outcome.kind,
        action: outcome.created ? "created" : "updated",
        id: outcome.id,
      });
    }
    return outcome.kind === "lead"
      ? { leadId: outcome.id, created: outcome.created }
      : { studentId: outcome.id, created: outcome.created };
  }

  async autoCreateLeadFromChat(
    actor: ActorContext,
    senderUserId: string,
    trigger: "chat" | "onboarding" = "chat",
  ): Promise<{ leadId: string | null; created: boolean }> {
    const outcome = await this.database.transaction<AutomaticIntakeOutcome>(
      (client) =>
        this.runAutomaticIntake(
          client as unknown as LeadIntakeQueryExecutor, actor, senderUserId,
        ),
    );
    await this.publishAutomaticIntake(actor, senderUserId, trigger, outcome);
    return this.toAutomaticIntakeResult(outcome);
  }

  private async runAutomaticIntake(
    client: LeadIntakeQueryExecutor, actor: ActorContext,
    senderUserId: string,
  ): Promise<AutomaticIntakeOutcome> {
    await client.query(`select pg_advisory_xact_lock(hashtext($1))`, [
      `lead-intake:${senderUserId.toLowerCase()}`,
    ]);
    const profileRes = await client.query<AutomaticIntakeProfile>(
      `select p.id as profile_id, p.first_name, p.last_name, p.phone
         from app.profiles p
         join app.users u on u.id = p.user_id
          and u.deleted_at is null and u.role = 'client'
        where p.user_id = $1 and p.deleted_at is null
        limit 1`,
      [senderUserId],
    );
    const profile = profileRes.rows[0];
    if (!profile) return { kind: "no_profile" };

    const existing = await this.findExistingAutomaticIntake(
      client, senderUserId, profile.profile_id,
    );
    if (existing) return existing;

    const phoneOutcome = await this.claimAutomaticPhoneMatch(
      client, actor, senderUserId, profile,
    );
    if (phoneOutcome) return phoneOutcome;
    return this.createAutomaticLead(client, actor, senderUserId, profile, null);
  }

  private async findExistingAutomaticIntake(
    client: LeadIntakeQueryExecutor, senderUserId: string,
    profileId: string,
  ): Promise<AutomaticIntakeEntityOutcome | null> {
    const studentId = await this.findStudentForUser(senderUserId, profileId, client);
    if (studentId) {
      return { kind: "student", id: studentId, created: false, linked: false };
    }
    const existingLead = await client.query<{ entity_id: string }>(
      `select link.entity_id
         from app.user_crm_links link
         join app.leads lead
           on lead.id = link.entity_id and lead.deleted_at is null
        where link.user_id = $1
          and link.entity_type = 'lead'
          and link.deleted_at is null
        order by link.confirmed_at desc nulls last, link.created_at desc
        limit 1`,
      [senderUserId],
    );
    const leadId = existingLead.rows[0]?.entity_id;
    return leadId ? { kind: "lead", id: leadId, created: false, linked: false } : null;
  }

  private async claimAutomaticPhoneMatch(
    client: LeadIntakeQueryExecutor, actor: ActorContext,
    senderUserId: string,
    profile: AutomaticIntakeProfile,
  ): Promise<AutomaticIntakeOutcome | null> {
    const matchedPhone = this.normalizeContactPhone(profile.phone);
    if (!matchedPhone) return null;
    await client.query(`select pg_advisory_xact_lock(hashtext($1))`, [
      `lead-phone:${matchedPhone}`,
    ]);
    const studentOutcome = await this.claimStudentPhoneCandidate(
      client, actor, senderUserId, profile.profile_id, matchedPhone,
    );
    if (studentOutcome) return studentOutcome;
    const leadOutcome = await this.claimLeadPhoneCandidate(
      client, actor, senderUserId, profile.profile_id, matchedPhone,
    );
    if (leadOutcome) return leadOutcome;
    return this.createAutomaticLead(
      client, actor, senderUserId, profile, matchedPhone,
    );
  }

  private async claimStudentPhoneCandidate(
    client: LeadIntakeQueryExecutor, actor: ActorContext,
    senderUserId: string, profileId: string,
    matchedPhone: string,
  ): Promise<AutomaticIntakeOutcome | null> {
    const candidates = await client.query<{ id: string | null; count: string }>(
      `with candidates as (
         select distinct student.id
           from app.students student
           join app.profiles profile
             on profile.id = student.profile_id and profile.deleted_at is null
           left join app.users owner
             on owner.id = profile.user_id and owner.deleted_at is null
          where student.deleted_at is null
            and profile.phone_normalized = $1
            and (owner.id is null or owner.id = $2 or owner.is_app_account = false)
            and not exists (
              select 1 from app.user_crm_links occupied
               where occupied.entity_type = 'student'
                 and occupied.entity_id = student.id
                 and occupied.deleted_at is null
                 and occupied.user_id <> $2
            )
       )
       select min(id::text)::uuid as id, count(*)::text as count
         from candidates`,
      [matchedPhone, senderUserId],
    );
    const count = Number(candidates.rows[0]?.count ?? 0);
    if (count > 1) return { kind: "review" };
    const studentId = candidates.rows[0]?.id;
    if (count !== 1 || !studentId) return null;
    return this.linkStudentIdentity(
      client, actor, senderUserId, profileId, matchedPhone, studentId,
    );
  }

  private async claimLeadPhoneCandidate(
    client: LeadIntakeQueryExecutor, actor: ActorContext,
    senderUserId: string, profileId: string,
    matchedPhone: string,
  ): Promise<AutomaticIntakeOutcome | null> {
    const candidates = await client.query<{ id: string | null; count: string }>(
      `with candidates as (
         select distinct lead.id
           from app.leads lead
          where lead.deleted_at is null
            and lead.phone_normalized = $1
            and not exists (
              select 1 from app.user_crm_links occupied
               where occupied.entity_type = 'lead'
                 and occupied.entity_id = lead.id
                 and occupied.deleted_at is null
                 and occupied.user_id <> $2
            )
       )
       select min(id::text)::uuid as id, count(*)::text as count
         from candidates`,
      [matchedPhone, senderUserId],
    );
    const count = Number(candidates.rows[0]?.count ?? 0);
    if (count > 1) return { kind: "review" };
    const leadId = candidates.rows[0]?.id;
    if (count !== 1 || !leadId) return null;
    return this.resolveLeadConversionCandidate(
      client, actor, senderUserId, profileId, matchedPhone, leadId,
    );
  }

  private async resolveLeadConversionCandidate(
    client: LeadIntakeQueryExecutor, actor: ActorContext,
    senderUserId: string, profileId: string,
    matchedPhone: string,
    leadId: string,
  ): Promise<AutomaticIntakeOutcome> {
    const converted = await client.query<{
      id: string | null;
      count: string;
      unavailable_count: string;
    }>(
      `select min(student.id::text)::uuid as id,
              count(*)::text as count,
              count(*) filter (
                where exists (
                  select 1 from app.user_crm_links occupied
                   where occupied.entity_type = 'student'
                     and occupied.entity_id = student.id
                     and occupied.deleted_at is null
                     and occupied.user_id <> $2
                )
                or (
                  owner.id is not null
                  and owner.id <> $2
                  and owner.is_app_account = true
                )
              )::text as unavailable_count
         from app.students student
         left join app.profiles profile
           on profile.id = student.profile_id and profile.deleted_at is null
         left join app.users owner
           on owner.id = profile.user_id and owner.deleted_at is null
        where student.lead_id = $1 and student.deleted_at is null`,
      [leadId, senderUserId],
    );
    const count = Number(converted.rows[0]?.count ?? 0);
    const unavailableCount = Number(converted.rows[0]?.unavailable_count ?? 0);
    if (count > 1 || unavailableCount > 0) return { kind: "review" };
    const studentId = converted.rows[0]?.id;
    if (count === 1 && studentId) {
      return this.linkStudentIdentity(
        client, actor, senderUserId, profileId, matchedPhone, studentId,
      );
    }
    return this.linkLeadIdentity(
      client, actor, senderUserId, matchedPhone, leadId,
    );
  }

  private async linkStudentIdentity(
    client: LeadIntakeQueryExecutor, actor: ActorContext,
    senderUserId: string, profileId: string,
    matchedPhone: string,
    studentId: string,
  ): Promise<AutomaticIntakeOutcome> {
    const linked = await client.query<{ entity_id: string }>(
      `insert into app.user_crm_links
         (user_id, entity_type, entity_id, matched_phone, link_source,
          created_by, confirmed_at)
       values ($1, 'student', $2, $3, 'auto_phone', $4, now())
       on conflict (entity_type, entity_id) where deleted_at is null
       do nothing
       returning entity_id`,
      [senderUserId, studentId, matchedPhone, actor.userId],
    );
    if (!linked.rows[0]) return { kind: "review" };
    const assigned = await mergeAndAssignStudentProfile(client, studentId, profileId);
    if (!assigned) {
      throw new ConflictException(
        "Карточка ученика изменилась во время привязки. Повторите попытку.",
      );
    }
    return { kind: "student", id: studentId, created: false, linked: true };
  }

  private async linkLeadIdentity(
    client: LeadIntakeQueryExecutor, actor: ActorContext,
    senderUserId: string, matchedPhone: string,
    leadId: string,
  ): Promise<AutomaticIntakeOutcome> {
    const linked = await client.query<{ entity_id: string }>(
      `insert into app.user_crm_links
         (user_id, entity_type, entity_id, matched_phone, link_source,
          created_by, confirmed_at)
       values ($1, 'lead', $2, $3, 'auto_phone', $4, now())
       on conflict (entity_type, entity_id) where deleted_at is null
       do nothing
       returning entity_id`,
      [senderUserId, leadId, matchedPhone, actor.userId],
    );
    return linked.rows[0]
      ? { kind: "lead", id: leadId, created: false, linked: true }
      : { kind: "review" };
  }

  private async createAutomaticLead(
    client: LeadIntakeQueryExecutor, actor: ActorContext,
    senderUserId: string, profile: AutomaticIntakeProfile,
    matchedPhone: string | null,
  ): Promise<AutomaticIntakeEntityOutcome> {
    const statusRes = await client.query<{ id: string }>(
      `select id
         from app.lead_statuses
        where stage_key = 'new'
           or lower(btrim(name)) in ('новый', 'новые')
        order by (stage_key = 'new') desc, sort_order, id
        limit 1`,
    );
    const newStatusId = statusRes.rows[0]?.id ?? null;
    const insertedLead = await client.query<{ id: string }>(
      `insert into app.leads (
         first_name, last_name, phone, source, source_id, status_id, created_by
       )
       select $1, $2, $3, source.display_name, source.id, $4, $5
         from app.lead_sources source
        where lower(btrim(source.canonical_name)) = 'app'
          and source.is_active
          and source.deleted_at is null
        limit 1
       returning id`,
      [profile.first_name, profile.last_name, profile.phone, newStatusId, actor.userId],
    );
    const createdLeadId = insertedLead.rows[0].id;
    await client.query(
      `insert into app.user_crm_links
         (user_id, entity_type, entity_id, matched_phone, link_source,
          created_by, confirmed_at)
       values ($1, 'lead', $2, $3, 'auto_phone', $4, now())
       on conflict do nothing`,
      [senderUserId, createdLeadId, matchedPhone, actor.userId],
    );
    return { kind: "lead", id: createdLeadId, created: true, linked: true };
  }

  private async publishAutomaticIntake(
    actor: ActorContext, senderUserId: string,
    trigger: "chat" | "onboarding",
    outcome: AutomaticIntakeOutcome,
  ): Promise<void> {
    if (!("id" in outcome)) return;
    if (!outcome.created && !outcome.linked) return;
    await this.recordAutomaticIntakeAudit(actor, senderUserId, trigger, outcome);
    this.realtime.emitCrmChanged({
      entity: outcome.kind,
      action: outcome.created ? "created" : "updated",
      id: outcome.id,
    });
  }

  private async recordAutomaticIntakeAudit(
    intakeActor: ActorContext, senderUserId: string,
    trigger: "chat" | "onboarding",
    outcome: AutomaticIntakeEntityOutcome,
  ): Promise<void> {
    try {
      await this.audit.record({
        actor: intakeActor,
        action: outcome.created
          ? "crm.lead_created"
          : "crm.client_user_linked",
        entityType: outcome.kind,
        entityId: outcome.id,
        metadata: {
          fromApp: true,
          userId: senderUserId,
          intakeTrigger: trigger,
        },
      });
    } catch (error) {
      this.logger.error(
        `Audit write failed for client intake ${outcome.kind}/${outcome.id}: ${String(error)}`,
      );
    }
  }

  private toAutomaticIntakeResult(
    outcome: AutomaticIntakeOutcome,
  ): { leadId: string | null; created: boolean } {
    if (outcome.kind === "review" || outcome.kind === "no_profile") {
      return { leadId: null, created: false };
    }
    return {
      leadId: outcome.kind === "lead" ? outcome.id : null,
      created: outcome.created,
    };
  }

  async countAppLeads(actor: ActorContext): Promise<{ count: number }> {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{ count: string }>(
      `select count(*)::text as count
       from app.leads lead
       join app.lead_sources source on source.id = lead.source_id
       where lower(btrim(source.canonical_name)) = 'app'
         and lead.deleted_at is null`,
    );
    return { count: Number(result.rows[0]?.count ?? 0) };
  }

  /**
   * Every way a chat user can already BE a student (правки №2, дубли):
   *  1. an explicit user_crm_links('student') row;
   *  2. a student on the user's own profile (in-app created);
   *  3. a student converted from the user's linked lead (lives on a NEW
   *     profile, so check 2 misses it — students.lead_id is the join).
   */
  private async findStudentForUser(
    userId: string,
    profileId: string,
    executor: LeadIntakeQueryExecutor = this.database,
  ): Promise<string | null> {
    const result = await executor.query<{ id: string }>(
      `
        select s.id
        from app.students s
        where s.deleted_at is null
          and (
            s.profile_id = $2
            or exists (
              select 1 from app.user_crm_links ucs
              where ucs.user_id = $1
                and ucs.entity_type = 'student'
                and ucs.entity_id = s.id
                and ucs.deleted_at is null
            )
            or exists (
              select 1 from app.user_crm_links ucl
              where ucl.user_id = $1
                and ucl.entity_type = 'lead'
                and ucl.entity_id = s.lead_id
                and ucl.deleted_at is null
            )
          )
        order by s.created_at desc
        limit 1
      `,
      [userId, profileId],
    );
    return result.rows[0]?.id ?? null;
  }

  private normalizeContactPhone(phone: string | null | undefined): string | null {
    return normalizePhoneRu(phone).canonical;
  }
}
