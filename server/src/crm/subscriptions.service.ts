import {
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { managerAdminRolesSql } from "../common/security/role-sql";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmListQuery } from "./dto/crm-list.query";
import { IssueSubscriptionDto } from "./dto/issue-subscription.dto";
import { UpdateSubscriptionPackageDto } from "./dto/update-subscription-package.dto";
import { UpsertSubscriptionPackageDto } from "./dto/upsert-subscription-package.dto";
import { CrmPolicy } from "./crm.policy";
import {
  audienceForHomework,
  audienceForLesson,
  audienceForStudent,
} from "./audience";
import { APPEAL_KEY, resolveAppealDate } from "./appeal-date";

interface SubscriptionRow {
  id: string;
  student_id: string;
  student_user_id: string | null;
  lessons_total: number;
  lessons_used: number;
  starts_at: Date | string | null;
  expires_at: Date | string | null;
  status: string;
  created_at: Date | string;
  updated_at: Date | string;
  package_name?: string | null;
  package_price?: number | string | null;
  /** Приход личного счёта, которым оплачен этот абонемент. */
  paid_amount?: number | string | null;
}

interface SubscriptionPackageRow {
  id: string;
  name: string;
  discipline_id: string | null;
  branch_id: string | null;
  lessons_total: number;
  price: string | number;
  validity_days: number | null;
  is_active: boolean;
  sort_order: number;
  created_at: Date | string;
}

interface IssuedSubscriptionRow {
  id: string;
  lessons_total: number | string;
  lessons_used: number | string;
  starts_at: Date | string | null;
  expires_at: Date | string | null;
  status: string;
  package_id: string | null;
  payment_id: string | null;
}

interface LeadConversionLeadRow {
  id: string;
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
  custom_data: Record<string, unknown> | null;
  branch_id: string | null;
  created_at: Date | string;
}

interface LeadConversionStudentRow {
  id: string;
  lead_id: string;
  status: string;
  custom_data: Record<string, unknown> | null;
  profile_id: string | null;
  profile_user_id: string | null;
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
  created_at: Date | string;
}

interface LeadConversionPaymentRow {
  id: string;
  student_id: string;
  amount: string | number;
  currency: string;
  payment_date: Date | string;
  method: string | null;
  notes: string | null;
}

interface LeadConversionSubscriptionRow extends IssuedSubscriptionRow {
  student_id: string;
}

interface LeadConversionLessonRow {
  id: string;
  student_id: string | null;
  group_id: string | null;
  lead_id: string | null;
  teacher_id: string | null;
}

interface ExistingLeadIssueRow extends LeadConversionStudentRow {
  subscription_id: string;
  lessons_total: string | number;
  lessons_used: string | number;
  starts_at: Date | string | null;
  expires_at: Date | string | null;
  subscription_status: string;
  package_id: string;
  payment_id: string;
  payment_amount: string | number;
  payment_currency: string;
  payment_date: Date | string;
  payment_method: string | null;
  payment_notes: string | null;
}

interface LeadIssueOutcome {
  student: LeadConversionStudentRow;
  subscription: LeadConversionSubscriptionRow;
  payment: LeadConversionPaymentRow;
  converted: boolean;
  issued: boolean;
  lessons: LeadConversionLessonRow[];
  homeworkIds: string[];
}

/**
 * Subscription domain, extracted from CrmService (SRP): student subscriptions,
 * subscription-package CRUD, and package issuance (payment + subscription in one
 * atomic statement). Touches `app.subscriptions` / `app.subscription_packages`
 * (and `app.payments` on issuance) and the shared database/audit/policy/realtime
 * collaborators. CrmService injects this back for the student-card aggregate.
 */
@Injectable()
export class SubscriptionsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
  ) {}

  private toSubscriptionDto(row: SubscriptionRow) {
    return {
      id: row.id,
      studentId: row.student_id,
      lessonsTotal: Number(row.lessons_total),
      lessonsUsed: Number(row.lessons_used),
      startsAt: row.starts_at,
      expiresAt: row.expires_at,
      status: row.status,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      packageName: row.package_name ?? null,
      packagePrice: row.package_price != null ? Number(row.package_price) : null,
      // «Оплачено» — не отдельная сущность, а приход личного счёта: выдача
      // абонемента кладёт его стоимость на счёт клиента (см. issueSubscription),
      // и здесь мы читаем именно этот приход. ✔ Решение владельца 16.07:
      // «оплату и переплату по абонементу считаем по личному счёту».
      paidAmount: row.paid_amount != null ? Number(row.paid_amount) : null,
    };
  }

  private toSubscriptionPackageDto(row: SubscriptionPackageRow) {
    return {
      id: row.id,
      name: row.name,
      disciplineId: row.discipline_id,
      branchId: row.branch_id,
      lessonsTotal: Number(row.lessons_total),
      price: Number(row.price),
      validityDays: row.validity_days,
      isActive: row.is_active,
      sortOrder: row.sort_order,
      createdAt: row.created_at,
    };
  }

  async listSubscriptions(actor: ActorContext, query: CrmListQuery) {
    const limit = Math.min(query.limit ?? 20, 100);
    const result = await this.database.query<SubscriptionRow>(
      `
        select sub.id, sub.student_id, p.user_id as student_user_id,
          sub.lessons_total, sub.lessons_used, sub.starts_at, sub.expires_at,
          sub.status, sub.created_at, sub.updated_at,
          pkg.name as package_name, pkg.price as package_price,
          -- «Оплачено»: приход личного счёта, которым закрыт абонемент.
          -- Отменённый платёж не считается оплатой.
          pay.amount as paid_amount
        from app.subscriptions sub
        join app.students s on s.id = sub.student_id and s.deleted_at is null
        left join app.subscription_packages pkg on pkg.id = sub.package_id
        left join app.payments pay on pay.id = sub.payment_id and pay.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where ($3::uuid is null or sub.student_id = $3)
          and (
            ${managerAdminRolesSql("$1")}
            or ($1::text = 'client' and p.user_id = $2)
            or (
              $1::text = 'client'
              and exists (
                select 1
                from app.user_crm_links link
                where link.entity_type = 'student'
                  and link.entity_id = s.id
                  and link.user_id = $2
                  and link.deleted_at is null
              )
            )
            or (
              $1::text = 'client'
              and exists (
                select 1
                from app.profiles account_profile
                join app.family_members account_member
                  on account_member.entity_type = 'profile'
                 and account_member.entity_id = account_profile.id
                 and account_member.role in ('parent', 'payer')
                 and account_member.deleted_at is null
                join app.families family
                  on family.id = account_member.family_id
                 and family.deleted_at is null
                join app.family_members student_member
                  on student_member.family_id = family.id
                 and student_member.entity_type = 'student'
                 and student_member.entity_id = s.id
                 and student_member.deleted_at is null
                where account_profile.user_id = $2
                  and account_profile.deleted_at is null
              )
            )
          )
        order by sub.expires_at desc nulls last, sub.created_at desc, sub.id desc
        limit $4
      `,
      [actor.role, actor.userId, query.studentId ?? null, limit],
    );
    return { items: result.rows.map((row) => this.toSubscriptionDto(row)) };
  }

  async listSubscriptionPackages(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const conditions: string[] = ["deleted_at is null"];
    const params: unknown[] = [];
    const q = query.q?.trim();
    if (q) {
      params.push(`%${q}%`);
      conditions.push(`name ilike $${params.length}`);
    }
    const limit = Math.min(query.limit ?? 100, 200);
    params.push(limit);
    const result = await this.database.query<SubscriptionPackageRow>(
      `
        select id, name, discipline_id, branch_id, lessons_total, price,
          validity_days, is_active, sort_order, created_at
        from app.subscription_packages
        where ${conditions.join(" and ")}
        order by sort_order asc, name asc
        limit $${params.length}
      `,
      params,
    );
    return {
      items: result.rows.map((row) => this.toSubscriptionPackageDto(row)),
    };
  }

  async createSubscriptionPackage(
    actor: ActorContext,
    dto: UpsertSubscriptionPackageDto,
  ) {
    this.policy.assertCanManageSubscriptionPackages(actor);
    const result = await this.database.query<SubscriptionPackageRow>(
      `
        insert into app.subscription_packages
          (name, discipline_id, branch_id, lessons_total, price,
           validity_days, is_active, sort_order)
        values ($1, $2, $3, $4, $5, $6, coalesce($7, true), coalesce($8, 0))
        returning id, name, discipline_id, branch_id, lessons_total, price,
          validity_days, is_active, sort_order, created_at
      `,
      [
        dto.name.trim(),
        dto.disciplineId ?? null,
        dto.branchId ?? null,
        dto.lessonsTotal,
        dto.price,
        dto.validityDays ?? null,
        dto.isActive ?? null,
        dto.sortOrder ?? null,
      ],
    );
    const pkg = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.subscription_package_created",
      entityType: "subscription_package",
      entityId: pkg.id,
    });
    return this.toSubscriptionPackageDto(pkg);
  }

  async updateSubscriptionPackage(
    actor: ActorContext,
    packageId: string,
    dto: UpdateSubscriptionPackageDto,
  ) {
    this.policy.assertCanManageSubscriptionPackages(actor);
    const result = await this.database.query<SubscriptionPackageRow>(
      `
        update app.subscription_packages
        set name = coalesce($2, name),
            discipline_id = coalesce($3, discipline_id),
            branch_id = coalesce($4, branch_id),
            lessons_total = coalesce($5, lessons_total),
            price = coalesce($6, price),
            validity_days = coalesce($7, validity_days),
            is_active = coalesce($8, is_active),
            sort_order = coalesce($9, sort_order),
            updated_at = now()
        where id = $1 and deleted_at is null
        returning id, name, discipline_id, branch_id, lessons_total, price,
          validity_days, is_active, sort_order, created_at
      `,
      [
        packageId,
        dto.name?.trim() ?? null,
        dto.disciplineId ?? null,
        dto.branchId ?? null,
        dto.lessonsTotal ?? null,
        dto.price ?? null,
        dto.validityDays ?? null,
        dto.isActive ?? null,
        dto.sortOrder ?? null,
      ],
    );
    const pkg = result.rows[0];
    if (!pkg) throw new NotFoundException("Абонемент не найден.");
    await this.audit.record({
      actor,
      action: "crm.subscription_package_updated",
      entityType: "subscription_package",
      entityId: pkg.id,
    });
    return this.toSubscriptionPackageDto(pkg);
  }

  async deleteSubscriptionPackage(actor: ActorContext, packageId: string) {
    this.policy.assertCanManageSubscriptionPackages(actor);
    const result = await this.database.query<{ id: string }>(
      `
        update app.subscription_packages
        set deleted_at = now(), updated_at = now()
        where id = $1 and deleted_at is null
        returning id
      `,
      [packageId],
    );
    const pkg = result.rows[0];
    if (!pkg) throw new NotFoundException("Абонемент не найден.");
    await this.audit.record({
      actor,
      action: "crm.subscription_package_deleted",
      entityType: "subscription_package",
      entityId: pkg.id,
    });
    return { success: true };
  }

  /**
   * Issue a subscription for an existing student: payment + subscription,
   * atomically. Imported students may legitimately retain lead_id without the
   * conversion marker introduced by migration 0072, so this path must remain
   * available to them. New lead conversion is enforced at the controller
   * boundary and only creates the student through issueLeadSubscription().
   */
  async issueSubscription(
    actor: ActorContext,
    studentId: string,
    dto: IssueSubscriptionDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.transaction(async (client) => {
      const student = await client.query<{ id: string }>(
        `
          select student.id
          from app.students student
          where student.id = $1 and student.deleted_at is null
          for update
        `,
        [studentId],
      );
      const studentRow = student.rows[0];
      if (!studentRow) throw new NotFoundException("Ученик не найден.");
      return client.query<IssuedSubscriptionRow>(
      `
        with pkg as (
          select id, branch_id, lessons_total, price, validity_days
          from app.subscription_packages
          where id = $2 and deleted_at is null and is_active = true
        ),
        pay as (
          insert into app.payments
            (student_id, amount, currency, payment_date, branch_id, notes, created_by)
          select $1, pkg.price, 'RUB', now(), pkg.branch_id, 'Покупка абонемента', $3
          from pkg
          returning id
        ),
        sub as (
          insert into app.subscriptions
            (student_id, lessons_total, lessons_used, starts_at, expires_at,
             status, package_id, payment_id)
          select $1, pkg.lessons_total, 0, current_date,
            case when pkg.validity_days is not null
              then (current_date + (pkg.validity_days || ' days')::interval)::date
              else null end,
            'active', pkg.id, pay.id
          from pkg, pay
          returning id, lessons_total, lessons_used, starts_at, expires_at,
            status, package_id, payment_id
        )
        select id, lessons_total, lessons_used, starts_at, expires_at,
          status, package_id, payment_id
        from sub
      `,
      [studentId, dto.packageId, actor.userId],
    );
    });
    const sub = result.rows[0];
    if (!sub) throw new NotFoundException("Абонемент не найден или неактивен.");
    await this.audit.record({
      actor,
      action: "crm.subscription_issued",
      entityType: "student",
      entityId: studentId,
      metadata: {
        subscriptionId: sub.id,
        packageId: sub.package_id,
        paymentId: sub.payment_id,
      },
    });
    const affectedUserIds = await audienceForStudent(this.database, studentId);
    this.realtime.emitCrmChanged({
      entity: "payment",
      action: "created",
      id: sub.payment_id,
      affectedUserIds,
    });
    this.realtime.emitCrmChanged({
      entity: "subscription",
      action: "created",
      id: sub.id,
      affectedUserIds,
    });
    return {
      id: sub.id,
      studentId,
      lessonsTotal: sub.lessons_total,
      lessonsUsed: sub.lessons_used,
      startsAt: sub.starts_at,
      expiresAt: sub.expires_at,
      status: sub.status,
      packageId: sub.package_id,
      paymentId: sub.payment_id,
    };
  }

  /**
   * The one legal lead conversion command: issue a package and atomically turn
   * the lead into a student. The durable conversion_lead_id key makes a retry
   * return the original payment/subscription instead of charging twice.
   */
  async issueLeadSubscription(
    actor: ActorContext,
    leadId: string,
    dto: IssueSubscriptionDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const outcome = await this.database.transaction(async (client) => {
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1::uuid::text, 0))",
        [leadId],
      );

      const existing = await this.loadExistingLeadIssue(client, leadId);
      if (existing) {
        if (existing.package_id !== dto.packageId) {
          throw new ConflictException(
            "Лид уже конвертирован с другим абонементом.",
          );
        }
        return this.outcomeFromExistingIssue(existing);
      }

      const leadResult = await client.query<LeadConversionLeadRow>(
        `
          select id, first_name, last_name, email, phone, custom_data,
            branch_id, created_at
          from app.leads
          where id = $1 and deleted_at is null
          for update
        `,
        [leadId],
      );
      const lead = leadResult.rows[0];
      if (!lead) throw new NotFoundException("Лид не найден.");

      const packageResult = await client.query<SubscriptionPackageRow>(
        `
          select id, name, discipline_id, branch_id, lessons_total, price,
            validity_days, is_active, sort_order, created_at
          from app.subscription_packages
          where id = $1 and deleted_at is null and is_active = true
          for share
        `,
        [dto.packageId],
      );
      const subscriptionPackage = packageResult.rows[0];
      if (!subscriptionPackage) {
        throw new NotFoundException("Абонемент не найден или неактивен.");
      }

      const activeStudent = await client.query<{ id: string }>(
        `
          select id
          from app.students
          where lead_id = $1 and deleted_at is null
          limit 1
        `,
        [leadId],
      );
      let studentId = activeStudent.rows[0]?.id;
      let converted = false;

      if (!studentId) {
        const customData = { ...(lead.custom_data ?? {}) };
        const appeal = resolveAppealDate(customData, lead.created_at);
        if (!customData[APPEAL_KEY] && appeal.value) {
          customData[APPEAL_KEY] = appeal.value;
        }
        if (!customData.sourceLeadId) customData.sourceLeadId = leadId;
        if (lead.email && !customData.sourceLeadEmail) {
          customData.sourceLeadEmail = lead.email;
        }

        const linkedProfile = await client.query<{ profile_id: string }>(
          `
            select profile.id as profile_id
            from app.user_crm_links link
            join app.users linked_user
              on linked_user.id = link.user_id
             and linked_user.deleted_at is null
             and linked_user.is_app_account = true
             and linked_user.role = 'client'
            join app.profiles profile
              on profile.user_id = linked_user.id
             and profile.deleted_at is null
            where link.entity_type = 'lead'
              and link.entity_id = $1
              and link.deleted_at is null
            order by link.confirmed_at desc nulls last, link.created_at desc
            limit 1
          `,
          [leadId],
        );

        if (linkedProfile.rows[0]) {
          const inserted = await client.query<{ id: string }>(
            `
              with updated_profile as (
                update app.profiles
                set first_name = coalesce($2, first_name),
                    last_name = coalesce($3, last_name),
                    phone = coalesce($4, phone),
                    updated_at = now()
                where id = $1 and deleted_at is null
                returning id
              )
              insert into app.students
                (profile_id, lead_id, status, custom_data, branch_id)
              select id, $5, 'active', $6::jsonb, $7
              from updated_profile
              returning id
            `,
            [
              linkedProfile.rows[0].profile_id,
              lead.first_name,
              lead.last_name,
              lead.phone,
              leadId,
              JSON.stringify(customData),
              lead.branch_id,
            ],
          );
          studentId = inserted.rows[0].id;
        } else {
          const fullName = [lead.first_name, lead.last_name]
            .filter(Boolean)
            .join(" ");
          const inserted = await client.query<{ id: string }>(
            `
              with identity as (
                select case
                  when $3::text is not null and not exists (
                    select 1 from app.users
                    where lower(email) = lower($3::text) and deleted_at is null
                  ) then lower($3::text)
                  else 'student-' || gen_random_uuid()::text || '@local.magicmusiccrm.invalid'
                end as email
              ), inserted_user as (
                insert into app.users
                  (email, full_name, phone, role, profile_completed, is_app_account)
                select email, $4, $5, 'client'::app.user_role, false, false
                from identity
                returning id
              ), inserted_profile as (
                insert into app.profiles
                  (user_id, first_name, last_name, phone)
                select id, $1, $2, $5
                from inserted_user
                returning id
              )
              insert into app.students
                (profile_id, lead_id, status, custom_data, branch_id)
              select id, $6, 'active', $7::jsonb, $8
              from inserted_profile
              returning id
            `,
            [
              lead.first_name,
              lead.last_name,
              lead.email,
              fullName,
              lead.phone,
              leadId,
              JSON.stringify(customData),
              lead.branch_id,
            ],
          );
          studentId = inserted.rows[0].id;
        }
        converted = true;
      }
      if (!studentId) throw new NotFoundException("Ученик не найден.");

      await client.query(
        `
          insert into app.client_conversion_links (
            lead_id, student_id, converted_by
          )
          values ($1, $2, $3)
          on conflict (lead_id) do nothing
        `,
        [leadId, studentId, actor.userId],
      );

      await client.query(
        `
          insert into app.user_crm_links (
            user_id, entity_type, entity_id, matched_phone,
            link_source, created_by, confirmed_at
          )
          select user_id, 'student', $2, matched_phone,
            link_source, coalesce(created_by, $3), coalesce(confirmed_at, now())
          from app.user_crm_links
          where entity_type = 'lead'
            and entity_id = $1
            and deleted_at is null
          on conflict do nothing
        `,
        [leadId, studentId, actor.userId],
      );

      // Keep the client's administration conversation attached to the CRM
      // entity after lead conversion. Some imported chats have no direct
      // lead_id and can only be resolved through their owner user's CRM link.
      await client.query(
        `
          update app.chats chat
          set student_id = $2, lead_id = null, updated_at = now()
          where chat.deleted_at is null
            and chat.slug is distinct from 'announcements'
            and (
              chat.lead_id = $1
              or (
                chat.type = 'administration'
                and exists (
                  select 1
                  from app.user_crm_links link
                  where link.user_id = chat.owner_user_id
                    and link.entity_type = 'lead'
                    and link.entity_id = $1
                    and link.deleted_at is null
                )
              )
            )
        `,
        [leadId, studentId],
      );

      // Preserve household access: the student replaces the lead as the child
      // member while parent/payer profile members remain unchanged.
      await client.query(
        `
          insert into app.family_members (
            family_id, entity_type, entity_id, role, is_primary_contact
          )
          select family_id, 'student', $2, role, is_primary_contact
          from app.family_members
          where entity_type = 'lead'
            and entity_id = $1
            and deleted_at is null
          on conflict (family_id, entity_type, entity_id)
          do update set role = excluded.role,
            is_primary_contact = excluded.is_primary_contact,
            deleted_at = null
        `,
        [leadId, studentId],
      );
      await client.query(
        `
          update app.family_members
          set deleted_at = now()
          where entity_type = 'lead'
            and entity_id = $1
            and deleted_at is null
        `,
        [leadId],
      );

      const reboundLessons = await client.query<LeadConversionLessonRow>(
        `
          update app.lessons
          set student_id = $2, lead_id = null, updated_at = now()
          where lead_id = $1
            and is_trial = true
            and deleted_at is null
          returning id, student_id, group_id, lead_id, teacher_id
        `,
        [leadId, studentId],
      );
      const reboundHomeworks = await client.query<{ id: string }>(
        `
          update app.lesson_homeworks
          set student_id = $2, lead_id = null, updated_at = now()
          where lead_id = $1 and deleted_at is null
          returning id
        `,
        [leadId, studentId],
      );

      const paymentResult = await client.query<LeadConversionPaymentRow>(
        `
          insert into app.payments
            (student_id, amount, currency, payment_date, branch_id, notes, created_by)
          values ($1, $2, 'RUB', now(), $3, 'Покупка абонемента', $4)
          returning id, student_id, amount, currency, payment_date, method, notes
        `,
        [
          studentId,
          subscriptionPackage.price,
          subscriptionPackage.branch_id ?? lead.branch_id,
          actor.userId,
        ],
      );
      const payment = paymentResult.rows[0];
      const subscriptionResult =
        await client.query<LeadConversionSubscriptionRow>(
          `
            insert into app.subscriptions (
              student_id, lessons_total, lessons_used, starts_at, expires_at,
              status, package_id, payment_id, conversion_lead_id
            )
            values (
              $1, $2, 0, current_date,
              case when $3::integer is not null
                then (current_date + ($3::text || ' days')::interval)::date
                else null end,
              'active', $4, $5, $6
            )
            returning id, student_id, lessons_total, lessons_used, starts_at,
              expires_at, status, package_id, payment_id
          `,
          [
            studentId,
            subscriptionPackage.lessons_total,
            subscriptionPackage.validity_days,
            subscriptionPackage.id,
            payment.id,
            leadId,
          ],
        );
      const student = await this.loadConversionStudent(client, studentId);
      if (!student) throw new NotFoundException("Ученик не найден.");

      return {
        student,
        subscription: subscriptionResult.rows[0],
        payment,
        converted,
        issued: true,
        lessons: reboundLessons.rows,
        homeworkIds: reboundHomeworks.rows.map((row) => row.id),
      } satisfies LeadIssueOutcome;
    });

    if (outcome.issued) {
      if (outcome.converted) {
        await this.audit.record({
          actor,
          action: "crm.student_created",
          entityType: "student",
          entityId: outcome.student.id,
          metadata: { leadId, trigger: "subscription" },
        });
      }
      await this.audit.record({
        actor,
        action: "crm.subscription_issued",
        entityType: "student",
        entityId: outcome.student.id,
        metadata: {
          leadId,
          subscriptionId: outcome.subscription.id,
          packageId: outcome.subscription.package_id,
          paymentId: outcome.payment.id,
        },
      });
      const affectedUserIds = await audienceForStudent(
        this.database,
        outcome.student.id,
      );
      this.realtime.emitCrmChanged({
        entity: "lead",
        action: "updated",
        id: leadId,
        affectedUserIds,
      });
      this.realtime.emitCrmChanged({
        entity: "student",
        action: outcome.converted ? "created" : "updated",
        id: outcome.student.id,
        affectedUserIds,
      });
      for (const lesson of outcome.lessons) {
        const lessonAudience = await audienceForLesson(
          this.database,
          lesson,
        );
        this.realtime.emitCrmChanged({
          entity: "lesson",
          action: "updated",
          id: lesson.id,
          affectedUserIds: lessonAudience,
        });
      }
      for (const homeworkId of outcome.homeworkIds) {
        const homeworkAudience = await audienceForHomework(
          this.database,
          homeworkId,
        );
        this.realtime.emitCrmChanged({
          entity: "homework",
          action: "updated",
          id: homeworkId,
          affectedUserIds: homeworkAudience,
        });
      }
      this.realtime.emitCrmChanged({
        entity: "payment",
        action: "created",
        id: outcome.payment.id,
        affectedUserIds,
      });
      this.realtime.emitCrmChanged({
        entity: "subscription",
        action: "created",
        id: outcome.subscription.id,
        affectedUserIds,
      });
    }

    return this.toLeadIssueDto(outcome);
  }

  private async loadExistingLeadIssue(
    client: PoolClient,
    leadId: string,
  ): Promise<ExistingLeadIssueRow | null> {
    const result = await client.query<ExistingLeadIssueRow>(
      `
        select student.id, student.lead_id, student.status,
          student.custom_data, student.profile_id,
          profile.user_id as profile_user_id,
          profile.first_name, profile.last_name, account.email, profile.phone,
          student.created_at,
          subscription.id as subscription_id,
          subscription.lessons_total, subscription.lessons_used,
          subscription.starts_at, subscription.expires_at,
          subscription.status as subscription_status,
          subscription.package_id, subscription.payment_id,
          payment.amount as payment_amount,
          payment.currency as payment_currency,
          payment.payment_date, payment.method as payment_method,
          payment.notes as payment_notes
        from app.subscriptions subscription
        join app.students student on student.id = subscription.student_id
        left join app.profiles profile on profile.id = student.profile_id
        left join app.users account on account.id = profile.user_id
        join app.payments payment on payment.id = subscription.payment_id
        where subscription.conversion_lead_id = $1
        limit 1
      `,
      [leadId],
    );
    return result.rows[0] ?? null;
  }

  private async loadConversionStudent(
    client: PoolClient,
    studentId: string,
  ): Promise<LeadConversionStudentRow | null> {
    const result = await client.query<LeadConversionStudentRow>(
      `
        select student.id, student.lead_id, student.status,
          student.custom_data, student.profile_id,
          profile.user_id as profile_user_id,
          profile.first_name, profile.last_name, account.email, profile.phone,
          student.created_at
        from app.students student
        left join app.profiles profile
          on profile.id = student.profile_id and profile.deleted_at is null
        left join app.users account
          on account.id = profile.user_id and account.deleted_at is null
        where student.id = $1 and student.deleted_at is null
        limit 1
      `,
      [studentId],
    );
    return result.rows[0] ?? null;
  }

  private outcomeFromExistingIssue(
    row: ExistingLeadIssueRow,
  ): LeadIssueOutcome {
    return {
      student: row,
      subscription: {
        id: row.subscription_id,
        student_id: row.id,
        lessons_total: row.lessons_total,
        lessons_used: row.lessons_used,
        starts_at: row.starts_at,
        expires_at: row.expires_at,
        status: row.subscription_status,
        package_id: row.package_id,
        payment_id: row.payment_id,
      },
      payment: {
        id: row.payment_id,
        student_id: row.id,
        amount: row.payment_amount,
        currency: row.payment_currency,
        payment_date: row.payment_date,
        method: row.payment_method,
        notes: row.payment_notes,
      },
      converted: false,
      issued: false,
      lessons: [],
      homeworkIds: [],
    };
  }

  private toLeadIssueDto(outcome: LeadIssueOutcome) {
    return {
      student: {
        id: outcome.student.id,
        leadId: outcome.student.lead_id,
        status: outcome.student.status,
        customData: outcome.student.custom_data ?? {},
        profileId: outcome.student.profile_id,
        profileUserId: outcome.student.profile_user_id,
        firstName: outcome.student.first_name,
        lastName: outcome.student.last_name,
        email: outcome.student.email,
        phone: outcome.student.phone,
        teacherUserIds: [],
        createdAt: outcome.student.created_at,
      },
      subscription: {
        id: outcome.subscription.id,
        studentId: outcome.subscription.student_id,
        lessonsTotal: Number(outcome.subscription.lessons_total),
        lessonsUsed: Number(outcome.subscription.lessons_used),
        startsAt: outcome.subscription.starts_at,
        expiresAt: outcome.subscription.expires_at,
        status: outcome.subscription.status,
        packageId: outcome.subscription.package_id,
        paymentId: outcome.subscription.payment_id,
      },
      payment: {
        id: outcome.payment.id,
        studentId: outcome.payment.student_id,
        amount: Number(outcome.payment.amount),
        currency: outcome.payment.currency,
        paymentDate: outcome.payment.payment_date,
        method: outcome.payment.method,
        notes: outcome.payment.notes,
      },
      converted: outcome.converted,
    };
  }
}
