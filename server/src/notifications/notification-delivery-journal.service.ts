import { ForbiddenException, Injectable } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import {
  branchIdExpr,
  currentActorRoleSql,
  managerBranchScopeSql,
} from "../crm/branch-scope";
import { DatabaseService } from "../db/database.service";
import { ListNotificationDeliveriesQuery } from "./dto/list-notification-deliveries.query";

interface DeliveryJournalRow {
  notification_id: string;
  notification_type: string;
  title: string;
  event_type: string | null;
  entity_type: string | null;
  entity_id: string | null;
  recipient_user_id: string;
  recipient_name: string;
  recipient_entity_type: string | null;
  recipient_entity_id: string | null;
  branch_id: string;
  branch_name: string | null;
  channel: string;
  provider: string;
  status: string;
  attempt_count: number | string;
  last_error: string | null;
  created_at: Date | string;
  updated_at: Date | string;
  total_count: string;
}

@Injectable()
export class NotificationDeliveryJournalService {
  constructor(private readonly database: DatabaseService) {}

  async list(actor: ActorContext, query: ListNotificationDeliveriesQuery) {
    await this.assertCurrentOperationalRole(actor);
    const now = new Date();
    const to = query.to ?? now.toISOString();
    const from =
      query.from ??
      new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const limit = Math.min(query.limit ?? 50, 200);
    const offset = Math.max(query.offset ?? 0, 0);
    const role = currentActorRoleSql("$8");
    const branchScope = managerBranchScopeSql({
      roleExpression: role,
      userIdExpression: "$8",
      branchExpression: "candidate.branch_id",
    });
    const result = await this.database.query<DeliveryJournalRow>(
      `with delivery as (
         select target.notification_id,
                target.user_id,
                target.channel::text as channel,
                target.provider,
                target.status::text as status,
                target.attempt_count,
                target.last_error,
                target.created_at,
                target.updated_at
           from app.notification_deliveries target
         union all
         select (outbox.payload->>'notificationId')::uuid,
                outbox.user_id,
                'email',
                'email_outbox',
                outbox.status::text,
                outbox.attempt_count,
                outbox.last_error,
                outbox.created_at,
                outbox.updated_at
           from app.email_outbox outbox
          where outbox.user_id is not null
            and outbox.payload->>'notificationId' ~* '^[0-9a-f-]{36}$'
       )
       select
         notification.id as notification_id,
         notification.type as notification_type,
         notification.title,
         notification.data->>'eventType' as event_type,
         notification.data->>'entityType' as entity_type,
         notification.data->>'entityId' as entity_id,
         delivery.user_id as recipient_user_id,
         coalesce(
           nullif(btrim(concat_ws(' ', profile.first_name, profile.last_name)), ''),
           account.email,
           'Без имени'
         ) as recipient_name,
         recipient_link.entity_type as recipient_entity_type,
         recipient_link.entity_id as recipient_entity_id,
         branch_context.branch_id,
         branch.name as branch_name,
         delivery.channel,
         delivery.provider,
         delivery.status,
         delivery.attempt_count,
         delivery.last_error,
         delivery.created_at,
         delivery.updated_at,
         count(*) over ()::text as total_count
       from delivery
       join app.notifications notification
         on notification.id = delivery.notification_id
       join app.users account
         on account.id = delivery.user_id and account.deleted_at is null
       left join app.profiles profile
         on profile.user_id = delivery.user_id and profile.deleted_at is null
       left join lateral (
         select candidate.branch_id
           from (
             select notification.data->>'branchId' as branch_id, 0 as priority
             where notification.data->>'branchId' is not null
             union all
             select lesson.branch_id::text, 1
               from app.lessons lesson
              where notification.data->>'entityType' = 'lesson'
                and lesson.id::text = notification.data->>'entityId'
                and lesson.deleted_at is null
             union all
             select task.branch_id::text, 1
               from app.shared_tasks task
              where notification.data->>'entityType' in ('task', 'shared_task')
                and task.id::text = notification.data->>'entityId'
             union all
             select ${branchIdExpr("student")} as branch_id, 1
               from app.students student
              where notification.data->>'entityType' = 'student'
                and student.id::text = notification.data->>'entityId'
                and student.deleted_at is null
             union all
             select ${branchIdExpr("lead")} as branch_id, 1
               from app.leads lead
              where notification.data->>'entityType' = 'lead'
                and lead.id::text = notification.data->>'entityId'
                and lead.deleted_at is null
             union all
             select assignment.branch_id::text, 2
               from app.user_crm_links link
               join app.staff_branch_assignments assignment
                 on assignment.staff_member_id = link.entity_id
                and assignment.deleted_at is null
              where link.user_id = delivery.user_id
                and link.entity_type = 'staff'
                and link.deleted_at is null
             union all
             select assignment.branch_id::text, 2
               from app.user_crm_links link
               join app.teacher_branches assignment
                 on assignment.teacher_id = link.entity_id
                and assignment.active_from <= current_date
                and (
                  assignment.active_until is null
                  or assignment.active_until >= current_date
                )
              where link.user_id = delivery.user_id
                and link.entity_type = 'teacher'
                and link.deleted_at is null
             union all
             select ${branchIdExpr("linked_student")} as branch_id, 2
               from app.user_crm_links link
               join app.students linked_student
                 on linked_student.id = link.entity_id
                and linked_student.deleted_at is null
              where link.user_id = delivery.user_id
                and link.entity_type = 'student'
                and link.deleted_at is null
             union all
             select ${branchIdExpr("linked_lead")} as branch_id, 2
               from app.user_crm_links link
               join app.leads linked_lead
                 on linked_lead.id = link.entity_id
                and linked_lead.deleted_at is null
              where link.user_id = delivery.user_id
                and link.entity_type = 'lead'
                and link.deleted_at is null
           ) candidate
          where candidate.branch_id is not null
            and ${branchScope}
            and ($3::uuid is null or candidate.branch_id = $3::text)
          order by candidate.priority, candidate.branch_id
          limit 1
       ) branch_context on true
       left join app.branches branch
         on branch.id::text = branch_context.branch_id
       left join lateral (
         select link.entity_type, link.entity_id::text as entity_id
           from app.user_crm_links link
          where link.user_id = delivery.user_id
            and link.deleted_at is null
          order by case link.entity_type
            when 'staff' then 0
            when 'teacher' then 1
            when 'student' then 2
            else 3
          end, link.created_at desc
          limit 1
       ) recipient_link on true
       where branch_context.branch_id is not null
         and notification.created_at >= $1::timestamptz
         and notification.created_at < $2::timestamptz
         and ($4::text is null or delivery.channel = $4::text)
         and ($5::text is null or delivery.status = $5::text)
       order by delivery.created_at desc, notification.id, delivery.user_id
       limit $6 offset $7`,
      [
        from,
        to,
        query.branchId ?? null,
        query.channel ?? null,
        query.status ?? null,
        limit,
        offset,
        actor.userId,
      ],
    );
    return {
      from,
      to,
      branchId: query.branchId ?? null,
      total: Number(result.rows[0]?.total_count ?? 0),
      items: result.rows.map((row) => ({
        notificationId: row.notification_id,
        notificationType: row.notification_type,
        title: row.title,
        eventType: row.event_type,
        entityType: normalizeEntityType(row.entity_type),
        entityId: row.entity_id,
        recipientUserId: row.recipient_user_id,
        recipientName: row.recipient_name,
        recipientEntityType: normalizeEntityType(row.recipient_entity_type),
        recipientEntityId: row.recipient_entity_id,
        branchId: row.branch_id,
        branchName: row.branch_name,
        channel: row.channel,
        provider: row.provider,
        status: row.status,
        attemptCount: Number(row.attempt_count),
        lastError: row.last_error,
        createdAt: toIso(row.created_at),
        updatedAt: toIso(row.updated_at),
      })),
    };
  }

  private async assertCurrentOperationalRole(actor: ActorContext) {
    const result = await this.database.query<{ role: string }>(
      `select role::text as role
         from app.users
        where id = $1 and deleted_at is null`,
      [actor.userId],
    );
    if (
      !["admin", "manager", "director", "system_admin"].includes(
        result.rows[0]?.role ?? "",
      )
    ) {
      throw new ForbiddenException(
        "Недостаточно прав для журнала доставки уведомлений.",
      );
    }
  }
}

function normalizeEntityType(value: string | null): string | null {
  return value === "shared_task" ? "task" : value;
}

function toIso(value: Date | string): string {
  return value instanceof Date ? value.toISOString() : value;
}
