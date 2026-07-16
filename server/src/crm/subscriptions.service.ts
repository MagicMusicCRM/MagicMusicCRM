import { Injectable, NotFoundException } from "@nestjs/common";
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
import { audienceForStudent } from "./audience";

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
  lessons_total: number;
  lessons_used: number;
  starts_at: Date | string | null;
  expires_at: Date | string | null;
  status: string;
  package_id: string | null;
  payment_id: string | null;
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
    this.policy.assertCanWriteCrm(actor);
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
    this.policy.assertCanWriteCrm(actor);
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
    this.policy.assertCanWriteCrm(actor);
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

  /** Issue a subscription from a package: payment + subscription, atomically. */
  async issueSubscription(
    actor: ActorContext,
    studentId: string,
    dto: IssueSubscriptionDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<IssuedSubscriptionRow>(
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
}
