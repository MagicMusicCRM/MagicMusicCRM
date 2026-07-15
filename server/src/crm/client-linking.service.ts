import { BadRequestException, Injectable } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { normalizePhoneRu, normalizedPhoneExpr } from "./phone.util";

/**
 * Manual app-user ↔ CRM-client (lead/student) linking via app.user_crm_links.
 * Phone-matched candidate discovery + explicit link upsert. Extracted from
 * CrmService (B5) — self-contained, no back-injection.
 */
@Injectable()
export class ClientLinkingService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly audit: AuditService,
  ) {}

  private assertClientEntityType(
    entityType: string,
  ): asserts entityType is "lead" | "student" {
    if (entityType !== "lead" && entityType !== "student") {
      throw new BadRequestException(
        "Тип сущности должен быть 'lead' или 'student'.",
      );
    }
  }

  // The client's raw phone: leads carry it directly, students inherit it from
  // their linked profile.
  private async getClientPhone(
    entityType: "lead" | "student",
    entityId: string,
  ): Promise<string | null> {
    if (entityType === "lead") {
      const result = await this.database.query<{ phone: string | null }>(
        `
          select phone
          from app.leads
          where id = $1 and deleted_at is null
          limit 1
        `,
        [entityId],
      );
      return result.rows[0]?.phone ?? null;
    }
    const result = await this.database.query<{ phone: string | null }>(
      `
        select p.phone
        from app.students s
        join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where s.id = $1 and s.deleted_at is null
        limit 1
      `,
      [entityId],
    );
    return result.rows[0]?.phone ?? null;
  }

  // App users currently linked to this client (via user_crm_links). For a
  // student we also fold in the student's own app account (their profile owner),
  // which may not have an explicit link row.
  async getClientLinkedUsers(
    actor: ActorContext,
    entityType: string,
    entityId: string,
  ) {
    this.policy.assertCanReadOperationalData(actor);
    this.assertClientEntityType(entityType);

    const linked = await this.database.query<{
      user_id: string;
      name: string;
      phone: string | null;
      link_source: string;
    }>(
      `
        select link.user_id,
          coalesce(
            nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''),
            u.email,
            'Пользователь'
          ) as name,
          p.phone,
          link.link_source
        from app.user_crm_links link
        join app.users u on u.id = link.user_id
          and u.deleted_at is null
          and u.is_app_account = true
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
        where link.deleted_at is null
          and link.entity_type = $1::app.crm_entity_type
          and link.entity_id = $2
        order by link.created_at desc, link.id desc
      `,
      [entityType, entityId],
    );

    const items = linked.rows.map((row) => ({
      userId: row.user_id,
      name: row.name,
      phone: row.phone,
      linkSource: row.link_source,
    }));

    if (entityType === "student") {
      const own = await this.database.query<{
        user_id: string;
        name: string;
        phone: string | null;
      }>(
        `
          select u.id as user_id,
            coalesce(
              nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''),
              u.email,
              'Пользователь'
            ) as name,
            p.phone
          from app.students s
          join app.profiles p on p.id = s.profile_id and p.deleted_at is null
          join app.users u on u.id = p.user_id
            and u.deleted_at is null
            and u.is_app_account = true
          where s.id = $1 and s.deleted_at is null
          limit 1
        `,
        [entityId],
      );
      const self = own.rows[0];
      if (self && !items.some((item) => item.userId === self.user_id)) {
        items.push({
          userId: self.user_id,
          name: self.name,
          phone: self.phone,
          linkSource: "self",
        });
      }
    }

    return { items };
  }

  // App users whose normalized phone matches the client's, excluding those
  // already linked to this entity. Empty when the client has no usable phone.
  async listClientUserCandidates(
    actor: ActorContext,
    entityType: string,
    entityId: string,
  ) {
    this.policy.assertCanReadOperationalData(actor);
    this.assertClientEntityType(entityType);

    const rawPhone = await this.getClientPhone(entityType, entityId);
    const normalizedPhone = this.normalizeContactPhone(rawPhone);
    if (!normalizedPhone) {
      return { items: [] };
    }

    const result = await this.database.query<{
      user_id: string;
      name: string;
      phone: string | null;
      email: string | null;
    }>(
      `
        select u.id as user_id,
          coalesce(
            nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''),
            u.email,
            'Пользователь'
          ) as name,
          p.phone,
          u.email
        from app.users u
        join app.profiles p on p.user_id = u.id and p.deleted_at is null
        where u.deleted_at is null
          and u.is_app_account = true
          and ${normalizedPhoneExpr("p.phone")} = $1
          and not exists (
            select 1
            from app.user_crm_links existing
            where existing.entity_type = $2::app.crm_entity_type
              and existing.entity_id = $3
              and existing.deleted_at is null
              and existing.user_id = u.id
          )
        order by u.created_at desc, u.id desc
        limit 50
      `,
      [normalizedPhone, entityType, entityId],
    );

    return {
      items: result.rows.map((row) => ({
        userId: row.user_id,
        name: row.name,
        phone: row.phone,
        email: row.email,
      })),
    };
  }

  // Manually link an app user to a client. Upserts on the active
  // (entity_type, entity_id) unique index so one client maps to one user.
  async linkUserToClient(
    actor: ActorContext,
    entityType: string,
    entityId: string,
    userId: string,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertClientEntityType(entityType);

    const userRow = await this.database.query<{ id: string }>(
      `
        select id
        from app.users
        where id = $1 and deleted_at is null and is_app_account = true
        limit 1
      `,
      [userId],
    );
    if (!userRow.rows[0]) {
      throw new BadRequestException("Пользователь приложения не найден.");
    }

    const rawPhone = await this.getClientPhone(entityType, entityId);
    const matchedPhone = this.normalizeContactPhone(rawPhone);

    await this.database.query(
      `
        insert into app.user_crm_links
          (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
        values ($1, $2::app.crm_entity_type, $3, $4, 'manual_phone', $5, now())
        on conflict (entity_type, entity_id) where deleted_at is null
        do update set
          user_id = excluded.user_id,
          matched_phone = excluded.matched_phone,
          link_source = 'manual_phone',
          deleted_at = null,
          confirmed_at = now()
      `,
      [userId, entityType, entityId, matchedPhone, actor.userId],
    );

    await this.audit.record({
      actor,
      action: "crm.client_user_linked",
      entityType,
      entityId,
      metadata: { userId },
    });

    return this.getClientLinkedUsers(actor, entityType, entityId);
  }

  // ponytail: 1-line wrapper copied from crm.service (retained callers keep
  // their copy). Trivial delegation to normalizePhoneRu.
  private normalizeContactPhone(phone: string | null | undefined): string | null {
    return normalizePhoneRu(phone).canonical;
  }
}
