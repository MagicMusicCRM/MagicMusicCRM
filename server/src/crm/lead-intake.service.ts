import { Injectable, Logger, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { LeadIntakePort } from "../common/lead-intake.port";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { normalizePhoneRu, normalizedPhoneExpr } from "./phone.util";

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
          select p.user_id
          from app.profiles p
          join app.users u on u.id = p.user_id and u.deleted_at is null
          where p.deleted_at is null
            and ${normalizedPhoneExpr("p.phone")} = $1
            and u.role = 'client'
          order by u.created_at desc
          limit 1
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
        select entity_type, entity_id
        from app.user_crm_links
        where user_id = $1 and deleted_at is null
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
    return { studentId, leadId };
  }

  async saveContactFromChat(
    actor: ActorContext,
    dto: { userId: string; as: "lead" | "student" },
  ) {
    this.policy.assertCanWriteCrm(actor);
    const profileResult = await this.database.query<{
      profile_id: string;
      user_id: string;
      first_name: string | null;
      last_name: string | null;
      phone: string | null;
    }>(
      `
        select p.id as profile_id, p.user_id, p.first_name, p.last_name, p.phone
        from app.profiles p
        join app.users u on u.id = p.user_id and u.deleted_at is null
        where p.user_id = $1 and p.deleted_at is null
        limit 1
      `,
      [dto.userId],
    );
    const profile = profileResult.rows[0];
    if (!profile) throw new NotFoundException("Пользователь чата не найден.");

    const firstName = (profile.first_name ?? "").trim() || "Без имени";
    const lastName = (profile.last_name ?? "").trim() || null;
    const phone = (profile.phone ?? "").trim() || null;
    const matchedPhone = this.normalizeContactPhone(phone);

    if (dto.as === "lead") {
      const existing = await this.database.query<{ entity_id: string }>(
        `
          select entity_id from app.user_crm_links
          where user_id = $1 and entity_type = 'lead' and deleted_at is null
          limit 1
        `,
        [profile.user_id],
      );
      if (existing.rows[0]) {
        return { leadId: existing.rows[0].entity_id, created: false };
      }
      // KVA-175: stamp the funnel entry status «Новый» so a manually-saved
      // lead doesn't land in «Без статуса» (mirrors C6 autoCreateLeadFromChat).
      const statusRow = await this.database.query<{ id: string }>(
        `select id from app.lead_statuses where lower(btrim(name)) = 'новый' limit 1`,
      );
      const defaultStatusId = statusRow.rows[0]?.id ?? null;
      const leadId = await this.database.transaction(async (client) => {
        const inserted = await client.query<{ id: string }>(
          `
            insert into app.leads (first_name, last_name, phone, source, status_id, created_by)
            values ($1, $2, $3, 'Чат', $4, $5)
            returning id
          `,
          [firstName, lastName, phone, defaultStatusId, actor.userId],
        );
        const id = inserted.rows[0].id;
        await client.query(
          `
            insert into app.user_crm_links
              (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
            values ($1, 'lead', $2, $3, 'manual_phone', $4, now())
            on conflict do nothing
          `,
          [profile.user_id, id, matchedPhone, actor.userId],
        );
        return id;
      });
      await this.audit.record({
        actor,
        action: "crm.lead_created",
        entityType: "lead",
        entityId: leadId,
        metadata: { fromChat: true, userId: profile.user_id },
      });
      return { leadId, created: true };
    }

    // as === "student": reuse the partner's existing profile (do not mint a new
    // user); dedup by profile so a client isn't doubled.
    const existingStudent = await this.database.query<{ id: string }>(
      `
        select id from app.students
        where profile_id = $1 and deleted_at is null
        limit 1
      `,
      [profile.profile_id],
    );
    if (existingStudent.rows[0]) {
      return { studentId: existingStudent.rows[0].id, created: false };
    }
    const studentId = await this.database.transaction(async (client) => {
      const inserted = await client.query<{ id: string }>(
        `
          insert into app.students (profile_id, status)
          values ($1, 'active')
          returning id
        `,
        [profile.profile_id],
      );
      const id = inserted.rows[0].id;
      await client.query(
        `
          insert into app.user_crm_links
            (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
          values ($1, 'student', $2, $3, 'manual_phone', $4, now())
          on conflict do nothing
        `,
        [profile.user_id, id, matchedPhone, actor.userId],
      );
      return id;
    });
    await this.audit.record({
      actor,
      action: "crm.student_created",
      entityType: "student",
      entityId: studentId,
      metadata: { fromChat: true, userId: profile.user_id },
    });
    return { studentId, created: true };
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
        [`autolead:${senderUserId}`],
      );

      // 2. Re-check the link inside the transaction (after the lock is held).
      const linkedRes = await client.query<{ entity_type: string; entity_id: string }>(
        `select entity_type, entity_id from app.user_crm_links
          where user_id = $1 and entity_type in ('lead', 'student') and deleted_at is null
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
        first_name: string | null;
        last_name: string | null;
        phone: string | null;
      }>(
        `select p.first_name, p.last_name, p.phone
           from app.profiles p
           join app.users u on u.id = p.user_id and u.deleted_at is null
          where p.user_id = $1 and p.deleted_at is null
          limit 1`,
        [senderUserId],
      );
      const profile = profileRes.rows[0];
      if (!profile) return { noProfile: true };

      // 4. Look up the «Новый» status (null fallback is fine).
      const statusRes = await client.query<{ id: string }>(
        `select id from app.lead_statuses where lower(btrim(name)) = 'новый' limit 1`,
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

    // 6. Audit only on actual creation, outside the transaction.
    await this.audit.record({
      actor,
      action: "crm.lead_created",
      entityType: "lead",
      entityId: sentinel.createdLeadId,
      metadata: { fromApp: true, userId: senderUserId },
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
      `select id from app.lead_statuses where lower(btrim(name)) = 'новый' limit 1`,
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
    await this.audit.record({
      action: "crm.lead_created",
      entityType: "lead",
      entityId: leadId,
      metadata: { fromSiteWebhook: true, source },
    });
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

  private normalizeContactPhone(phone: string | null | undefined): string | null {
    return normalizePhoneRu(phone).canonical;
  }
}
