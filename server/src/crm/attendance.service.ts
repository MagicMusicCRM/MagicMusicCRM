import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isManagerOrAdminRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { UpsertAttendanceDto } from "./dto/upsert-attendance.dto";

interface LessonAccessRow {
  id: string;
  student_id: string | null;
  group_id: string | null;
  teacher_user_id: string | null;
}

interface AttendanceStudentRow {
  student_id: string;
  first_name: string | null;
  last_name: string | null;
}

interface AttendanceParticipationRow {
  student_id: string;
  status: string;
  pass_reason: string | null;
  attendance_kind?: string | null;
  charge_share?: string | number | null;
  charged_hours?: string | number | null;
}

/**
 * Lesson-attendance domain (KVA-237), extracted from CrmService (SRP): read the
 * attendance sheet for a lesson, and mark it — which idempotently reconciles the
 * per-participation subscription charge by delta and optionally notifies the
 * client. Touches `app.lesson_participation` / `app.lessons` / `app.subscriptions`
 * and the shared db/audit/notifications collaborators. Access is checked inline
 * (manager/admin, or the lesson's own teacher); no CrmPolicy dependency.
 */
@Injectable()
export class AttendanceService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly notifications: NotificationsService,
  ) {}

  async getLessonAttendance(actor: ActorContext, lessonId: string) {
    const lesson = await this.findLessonForAttendance(actor, lessonId);
    const students = await this.listAttendanceStudents(lesson);
    const participations =
      await this.database.query<AttendanceParticipationRow>(
        `
        select student_id, status, pass_reason,
          attendance_kind, charge_share, charged_hours
        from app.lesson_participation
        where lesson_id = $1
      `,
        [lessonId],
      );
    const byStudentId = new Map(
      participations.rows.map((row) => [row.student_id, row]),
    );

    return {
      lessonId,
      students: students.map((row) => {
        const participation = byStudentId.get(row.student_id);
        return {
          studentId: row.student_id,
          studentName:
            `${row.first_name ?? ""} ${row.last_name ?? ""}`.trim() ||
            "Без имени",
          status: this.toAttendanceStatus(participation?.status),
          kind: participation?.attendance_kind ?? null,
          chargeShare:
            participation?.charge_share != null
              ? Number(participation.charge_share)
              : null,
          chargedHours:
            participation?.charged_hours != null
              ? Number(participation.charged_hours)
              : null,
          passReason: participation?.pass_reason ?? "",
        };
      }),
    };
  }

  async upsertLessonAttendance(
    actor: ActorContext,
    lessonId: string,
    dto: UpsertAttendanceDto,
  ) {
    const lesson = await this.findLessonForAttendance(actor, lessonId);
    const students = await this.listAttendanceStudents(lesson);
    const allowedStudentIds = new Set(students.map((row) => row.student_id));
    const items = dto.items ?? [];
    for (const item of items) {
      if (!allowedStudentIds.has(item.studentId)) {
        throw new BadRequestException("Ученик не относится к этому уроку.");
      }
    }

    for (const item of items) {
      // KVA-237: kind — источник истины; легаси-status маппится в kind,
      // бинарный status выводится из kind (present = клиент был на занятии).
      const kind =
        item.kind ??
        (item.status === "absent" ? "unpaid_miss" : "attended");
      const status = ["attended", "free_lesson", "partially_paid"].includes(
        kind,
      )
        ? "present"
        : "absent";
      const chargeShare =
        kind === "partially_paid" ? (item.chargeShare ?? 0.5) : 1;
      await this.database.query(
        `
          insert into app.lesson_participation (
            lesson_id, student_id, status, pass_reason, attendance_kind, charge_share
          )
          values ($1, $2, $3, $4, $5, $6)
          on conflict (lesson_id, student_id)
          do update set status = excluded.status,
            pass_reason = excluded.pass_reason,
            attendance_kind = excluded.attendance_kind,
            charge_share = excluded.charge_share
        `,
        [
          lessonId,
          item.studentId,
          status,
          item.passReason?.trim() || null,
          kind,
          chargeShare,
        ],
      );
    }

    // KVA-237: списание с абонемента по таблице правил (доля от типа
    // посещения), идемпотентно по дельте — смена статуса задним числом
    // пересчитывает уже списанные часы.
    for (const item of items) {
      await this.reconcileSubscriptionUsage(lessonId, item.studentId);
    }

    // «Уведомить об изменениях» (модалка HolliHop): in-app+push клиенту.
    if (dto.notifyClient) {
      await this.notifyAttendanceChanged(lessonId, items.map((i) => i.studentId));
    }

    await this.database.query(
      `
        update app.lessons
        set status = 'completed', updated_at = now()
        where id = $1 and deleted_at is null
      `,
      [lessonId],
    );
    await this.audit.record({
      actor,
      action: "crm.lesson_attendance_updated",
      entityType: "lesson",
      entityId: lessonId,
    });
    return this.getLessonAttendance(actor, lessonId);
  }

  /** KVA-237: доля списания часа с абонемента по типу посещения. */
  private static chargeShareForKind(kind: string, share: number): number {
    switch (kind) {
      case "attended":
      case "paid_miss":
        return 1;
      case "partially_paid":
        return share;
      default: // unpaid_miss, free_lesson — час клиента сохраняется
        return 0;
    }
  }

  /**
   * KVA-237 (растёт из P5b-4): идемпотентная сверка списания per-participation
   * по ДЕЛЬТЕ. charged_hours хранит фактически списанное; target считается из
   * типа посещения (см. chargeShareForKind). Повтор того же статуса — no-op;
   * смена статуса задним числом дописывает/возвращает ровно разницу.
   * Выбор абонемента: свой активный, иначе — члена семьи (KVA-235).
   */
  private async reconcileSubscriptionUsage(lessonId: string, studentId: string) {
    // Read-compute-write on charged_hours/lessons_used: runs inside one
    // transaction serialized by a per-participation advisory lock, otherwise a
    // double-submit (teacher retry) reads charged=0 twice and decrements the
    // subscription twice for one attended lesson.
    await this.database.transaction(async (client) => {
      await client.query(
        `select pg_advisory_xact_lock(hashtext('attendance:' || $1 || ':' || $2))`,
        [lessonId, studentId],
      );
      const state = await client.query<{
        attendance_kind: string;
        charge_share: string | number;
        charged_hours: string | number;
        subscription_id: string | null;
        hours: string | number;
      }>(
        `
        select lp.attendance_kind, lp.charge_share, lp.charged_hours,
          lp.subscription_id,
          coalesce(l.duration_minutes, 60)::numeric / 60 as hours
        from app.lesson_participation lp
        join app.lessons l on l.id = lp.lesson_id
        where lp.lesson_id = $1 and lp.student_id = $2
      `,
        [lessonId, studentId],
      );
      const row = state.rows[0];
      if (!row) return;
      const hours = Number(row.hours);
      const target =
        Math.round(
          hours *
            AttendanceService.chargeShareForKind(
              row.attendance_kind,
              Number(row.charge_share),
            ) *
            100,
        ) / 100;
      const charged = Number(row.charged_hours);
      const delta = Math.round((target - charged) * 100) / 100;
      if (delta === 0) return;

      if (delta > 0) {
        // Дописываем: на уже привязанный абонемент, иначе подбираем (свой →
        // семейный). Если абонемента нет — списывать не с чего, charged не растёт.
        await client.query(
          `
          with pick as (
            select s.id
            from app.subscriptions s
            where s.id = $3::uuid
            union all
            (
              select s.id
              from app.subscriptions s
              where $3::uuid is null
                and s.status = 'active'
                and s.lessons_used < s.lessons_total
                and (
                  s.student_id = $2
                  or s.student_id in (
                    select fm2.entity_id
                    from app.family_members fm1
                    join app.family_members fm2
                      on fm2.family_id = fm1.family_id
                      and fm2.entity_type = 'student'
                      and fm2.deleted_at is null
                    where fm1.entity_type = 'student'
                      and fm1.entity_id = $2
                      and fm1.deleted_at is null
                  )
                )
              order by (s.student_id = $2) desc,
                s.expires_at asc nulls last, s.created_at asc
              limit 1
            )
            limit 1
          ),
          dec as (
            update app.subscriptions s
            set lessons_used = lessons_used + $4::numeric, updated_at = now()
            from pick where s.id = pick.id
            returning s.id
          )
          update app.lesson_participation lp
          set subscription_id = (select id from dec),
            charged_hours = $5::numeric
          where lp.lesson_id = $1 and lp.student_id = $2
            and exists (select 1 from dec)
        `,
          [lessonId, studentId, row.subscription_id, delta, target],
        );
        return;
      }

      // Возвращаем часть/всё: только на привязанном абонементе.
      if (!row.subscription_id) {
        await client.query(
          `update app.lesson_participation set charged_hours = $3
         where lesson_id = $1 and student_id = $2`,
          [lessonId, studentId, target],
        );
        return;
      }
      await client.query(
        `
        with inc as (
          update app.subscriptions s
          set lessons_used = greatest(lessons_used + $4::numeric, 0),
            updated_at = now()
          where s.id = $3
          returning s.id
        )
        update app.lesson_participation lp
        set charged_hours = $5::numeric,
          subscription_id = case when $5::numeric = 0 then null else lp.subscription_id end
        from inc
        where lp.lesson_id = $1 and lp.student_id = $2
      `,
        [lessonId, studentId, row.subscription_id, delta, target],
      );
    });
  }

  /** KVA-237: пуш/in-app «изменение по занятию» клиентам с аккаунтами. */
  private async notifyAttendanceChanged(lessonId: string, studentIds: string[]) {
    if (!studentIds.length) return;
    const users = await this.database.query<{
      user_id: string;
      scheduled_at: Date | string;
    }>(
      `
        select p.user_id, l.scheduled_at
        from app.students s
        join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        join app.lessons l on l.id = $1
        where s.id = any($2::uuid[]) and s.deleted_at is null
          and p.user_id is not null
      `,
      [lessonId, studentIds],
    );
    for (const row of users.rows) {
      const when = new Date(String(row.scheduled_at));
      const dateLabel = Number.isNaN(when.getTime())
        ? ""
        : ` ${when.toLocaleDateString("ru-RU", { day: "2-digit", month: "2-digit", timeZone: "Europe/Moscow" })}`;
      await this.notifications
        .notifyUser({
          userId: row.user_id,
          title: "Изменение по занятию",
          body: `Статус вашего занятия${dateLabel} обновлён. Подробности в приложении.`,
          data: { lessonId },
          channels: ["in_app", "push"],
        })
        .catch(() => undefined); // уведомление не должно ронять посещаемость
    }
  }

  private async findLessonForAttendance(
    actor: ActorContext,
    lessonId: string,
  ): Promise<LessonAccessRow> {
    const result = await this.database.query<LessonAccessRow>(
      `
        select l.id, l.student_id, l.group_id, tp.user_id as teacher_user_id
        from app.lessons l
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where l.id = $1 and l.deleted_at is null
        limit 1
      `,
      [lessonId],
    );
    const lesson = result.rows[0];
    if (!lesson) throw new NotFoundException("Урок не найден.");
    if (isManagerOrAdminRole(actor.role)) return lesson;
    if (actor.role === "teacher" && lesson.teacher_user_id === actor.userId) {
      return lesson;
    }
    throw new NotFoundException("Урок не найден.");
  }

  private async listAttendanceStudents(
    lesson: LessonAccessRow,
  ): Promise<AttendanceStudentRow[]> {
    const result = await this.database.query<AttendanceStudentRow>(
      `
        select s.id as student_id, p.first_name, p.last_name
        from app.students s
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where s.deleted_at is null
          and (
            ($1::uuid is not null and s.id = $1)
            or exists (
              select 1
              from app.group_students gs
              where gs.student_id = s.id
                and gs.left_at is null
                and gs.group_id = $2
            )
          )
        order by p.last_name nulls last, p.first_name nulls last, s.id
      `,
      [lesson.student_id, lesson.group_id],
    );
    return result.rows;
  }

  private toAttendanceStatus(status: string | undefined): "present" | "absent" {
    if (status === "absent" || status === "missed" || status === "no_show") {
      return "absent";
    }
    return "present";
  }
}
