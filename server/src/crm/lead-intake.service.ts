import { Injectable, Logger, NotFoundException } from "@nestjs/common";
import type { QueryResult, QueryResultRow } from "pg";
import { AuditService } from "../audit/audit.service";
import { LeadIntakePort } from "../common/lead-intake.port";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { normalizePhoneRu, normalizedPhoneExpr } from "./phone.util";

interface LeadIntakeQueryExecutor {
  query<T extends QueryResultRow = QueryResultRow>(
    query: string,
    params?: unknown[],
  ): Promise<QueryResult<T>>;
}

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
    private readonly notifications: NotificationsService,
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
          `select min(id::text)::uuid as id
           from app.lead_statuses
           where lower(btrim(name)) = 'новый'
           having count(*) = 1`,
        );
        const inserted = await client.query<{ id: string }>(
          `insert into app.leads
             (first_name, last_name, phone, source, status_id, created_by)
           values ($1, $2, $3, 'Чат', $4, $5)
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
        `insert into app.students (profile_id, status, lead_id)
         values ($1, 'active', $2)
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
  ): Promise<{ leadId: string | null; created: boolean }> {
    type Sentinel =
      | { linkedLeadId: string | null }
      | { noProfile: true }
      | { createdLeadId: string; leadName: string };

    const sentinel = await this.database.transaction<Sentinel>(async (client) => {
      // 1. Acquire an advisory lock scoped to this transaction — serializes
      //    concurrent autoCreateLeadFromChat calls for the same senderUserId.
      await client.query(
        `select pg_advisory_xact_lock(hashtext($1))`,
        [`lead-intake:${senderUserId.toLowerCase()}`],
      );

      // 2. Re-check the link inside the transaction (after the lock is held).
      const linkedRes = await client.query<{ entity_type: string; entity_id: string }>(
        `select link.entity_type, link.entity_id
          from app.user_crm_links link
          left join app.leads lead
            on link.entity_type = 'lead'
           and lead.id = link.entity_id
           and lead.deleted_at is null
          left join app.students student
            on link.entity_type = 'student'
           and student.id = link.entity_id
           and student.deleted_at is null
          where link.user_id = $1
            and link.entity_type in ('lead', 'student')
            and link.deleted_at is null
            and (
              (link.entity_type = 'lead' and lead.id is not null)
              or (link.entity_type = 'student' and student.id is not null)
            )
          limit 1`,
        [senderUserId],
      );
      if (linkedRes.rows[0]) {
        const existing = linkedRes.rows[0];
        return {
          linkedLeadId: existing.entity_type !== "student" ? existing.entity_id : null,
        };
      }

      // 3. Fetch the user profile.
      const profileRes = await client.query<{
        profile_id: string;
        first_name: string | null;
        last_name: string | null;
        phone: string | null;
      }>(
        `select p.id as profile_id, p.first_name, p.last_name, p.phone
           from app.profiles p
           join app.users u on u.id = p.user_id
            and u.deleted_at is null and u.role = 'client'
          where p.user_id = $1 and p.deleted_at is null
          limit 1`,
        [senderUserId],
      );
      const profile = profileRes.rows[0];
      if (!profile) return { noProfile: true };

      const existingStudent = await this.findStudentForUser(
        senderUserId,
        profile.profile_id,
        client as unknown as LeadIntakeQueryExecutor,
      );
      if (existingStudent) {
        return { linkedLeadId: null };
      }

      // 4. Look up the «Новый» status (null fallback is fine).
      const statusRes = await client.query<{ id: string }>(
        `select min(id::text)::uuid as id
         from app.lead_statuses
         where lower(btrim(name)) = 'новый'
         having count(*) = 1`,
      );
      const newStatusId = statusRes.rows[0]?.id ?? null;
      const matchedPhone = this.normalizeContactPhone(profile.phone);

      // 5. Insert the lead and the link row in the same transaction.
      const insertedLead = await client.query<{ id: string }>(
        `insert into app.leads (first_name, last_name, phone, source, status_id, created_by)
         values ($1, $2, $3, 'Через приложение', $4, $5)
         returning id`,
        [profile.first_name, profile.last_name, profile.phone, newStatusId, actor.userId],
      );
      const createdLeadId = insertedLead.rows[0].id;
      await client.query(
        `insert into app.user_crm_links
           (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
         values ($1, 'lead', $2, $3, 'auto_phone', $4, now())
         on conflict do nothing`,
        [senderUserId, createdLeadId, matchedPhone, actor.userId],
      );
      return {
        createdLeadId,
        leadName:
          [profile.first_name, profile.last_name].filter(Boolean).join(" ").trim() ||
          "Без имени",
      };
    });

    if ("linkedLeadId" in sentinel) {
      return { leadId: sentinel.linkedLeadId, created: false };
    }
    if ("noProfile" in sentinel) {
      return { leadId: null, created: false };
    }

    // The lead/link transaction is already committed. An unavailable audit
    // sink must not turn a successfully persisted first message into a 5xx
    // retry (and a duplicate user-visible message).
    try {
      await this.audit.record({
        actor,
        action: "crm.lead_created",
        entityType: "lead",
        entityId: sentinel.createdLeadId,
        metadata: { fromApp: true, userId: senderUserId },
      });
    } catch (error) {
      this.logger.error(
        `Audit write failed for auto-created lead ${sentinel.createdLeadId}: ${String(error)}`,
      );
    }
    this.realtime.emitCrmChanged({
      entity: "lead",
      action: "created",
      id: sentinel.createdLeadId,
    });
    this.notifyNewLeadSafe(sentinel.createdLeadId, sentinel.leadName, "Через приложение");
    return { leadId: sentinel.createdLeadId, created: true };
  }

  // Public site form → lead. No actor: the caller is the webhook endpoint
  // authenticated by a shared secret, so created_by stays null and the funnel
  // entry status «Новый» is stamped like the chat-created leads do.
  async createLeadFromSiteWebhook(dto: {
    name: string;
    phone: string;
    email?: string;
    discipline?: string;
    comment?: string;
    source?: string;
  }): Promise<{ leadId: string }> {
    // Keep the canonical +7 form when the phone normalizes, otherwise store
    // the raw value — losing a site lead over formatting is worse than a
    // messy phone that a manager can fix by hand.
    const phone = normalizePhoneRu(dto.phone).canonical ?? dto.phone.trim();
    const source = dto.source?.trim() || "site";
    const notes =
      [
        dto.discipline?.trim() ? `Дисциплина: ${dto.discipline.trim()}` : null,
        dto.comment?.trim() || null,
      ]
        .filter(Boolean)
        .join("\n") || null;
    const statusRow = await this.database.query<{ id: string }>(
      `select min(id::text)::uuid as id
       from app.lead_statuses
       where lower(btrim(name)) = 'новый'
       having count(*) = 1`,
    );
    const inserted = await this.database.query<{ id: string }>(
      `
        insert into app.leads (first_name, phone, email, source, notes, status_id)
        values ($1, $2, $3, $4, $5, $6)
        returning id
      `,
      [
        dto.name.trim(),
        phone,
        dto.email?.trim().toLowerCase() || null,
        source,
        notes,
        statusRow.rows[0]?.id ?? null,
      ],
    );
    const leadId = inserted.rows[0].id;
    try {
      await this.audit.record({
        action: "crm.lead_created",
        entityType: "lead",
        entityId: leadId,
        metadata: { fromSiteWebhook: true, source },
      });
    } catch (error) {
      // The webhook has no caller-supplied idempotency key. Returning 5xx after
      // the lead insert committed would invite a retry and duplicate the lead.
      this.logger.error(
        `Audit write failed for site lead ${leadId}: ${String(error)}`,
      );
    }
    this.realtime.emitCrmChanged({ entity: "lead", action: "created", id: leadId });
    this.notifyNewLeadSafe(leadId, dto.name.trim(), source);
    return { leadId };
  }

  async countAppLeads(actor: ActorContext): Promise<{ count: number }> {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{ count: string }>(
      `select count(*)::text as count from app.leads where source = 'Через приложение' and deleted_at is null`,
    );
    return { count: Number(result.rows[0]?.count ?? 0) };
  }

  // ponytail: fire-and-forget notify, copied from LeadsService (updateLead
  // keeps its own copy); a notification failure must never break creation.
  private notifyNewLeadSafe(leadId: string, name: string, source: string): void {
    try {
      void this.notifications
        .notifyNewLead({ leadId, name, source })
        .catch((error: unknown) => {
          this.logger.warn(
            `New lead notification failed for ${leadId}: ${String(error)}`,
          );
        });
    } catch (error: unknown) {
      this.logger.warn(
        `New lead notification failed for ${leadId}: ${String(error)}`,
      );
    }
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
