import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isManagerOrAdminRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { audienceForStudent } from "./audience";
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
    // Статус занятия и посещаемость двигают списание с абонемента и расчёт ЗП —
    // это работа администратора и старше, не педагога (заказчик, правила ролей).
    // Педагог по-прежнему видит урок и может оставить комментарий/ДЗ (другие
    // эндпоинты), но статус «был/не пришёл» и тип занятия ставит только админ+.
    if (!isManagerOrAdminRole(actor.role)) {
      throw new ForbiddenException(
        "Статус занятия и посещаемость может изменять только администратор и выше.",
      );
    }
    const items = dto.items ?? [];
    if (items.length === 0) {
      throw new BadRequestException(
        "Нельзя завершить занятие без отметок посещаемости.",
      );
    }
    const lesson = await this.findLessonForAttendance(actor, lessonId);
    const students = await this.listAttendanceStudents(lesson);
    const allowedStudentIds = new Set(students.map((row) => row.student_id));
    const submittedStudentIds = new Set(items.map((item) => item.studentId));
    if (
      submittedStudentIds.size !== items.length ||
      submittedStudentIds.size !== allowedStudentIds.size
    ) {
      throw new BadRequestException(
        "Перед завершением занятия отметьте посещаемость всех участников.",
      );
    }
    await this.database.transaction(async (client) => {
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
      // subscription_id pins WHICH subscription pays. reconcileSubscriptionUsage
      // reads it back: set → charge exactly that one (this is how a client pays
      // for someone outside their family); null → it falls back to the
      // student's own subscription, then a family member's.
      if (item.subscriptionId) {
        const exists = await client.query<{ id: string }>(
          `select id from app.subscriptions where id = $1`,
          [item.subscriptionId],
        );
        if (!exists.rows[0]) {
          throw new NotFoundException("Абонемент не найден.");
        }
      }
      const participation = await client.query<{ id: string }>(
        `
          insert into app.lesson_participation (
            lesson_id, student_id, status, pass_reason, attendance_kind,
            charge_share, subscription_id
          )
          values ($1, $2, $3, $4, $5, $6, $7)
          on conflict (lesson_id, student_id)
          do update set status = excluded.status,
            pass_reason = excluded.pass_reason,
            attendance_kind = excluded.attendance_kind,
            charge_share = excluded.charge_share,
            -- Keep an existing pin when the caller does not send one: an
            -- attendance edit must not silently move the charge to another
            -- subscription.
            subscription_id = coalesce(
              excluded.subscription_id, app.lesson_participation.subscription_id
            )
          where excluded.subscription_id is null
            or app.lesson_participation.subscription_id is not distinct from excluded.subscription_id
            or app.lesson_participation.charged_hours = 0
          returning id
        `,
        [
          lessonId,
          item.studentId,
          status,
          item.passReason?.trim() || null,
          kind,
          chargeShare,
          item.subscriptionId ?? null,
        ],
      );
      if (item.subscriptionId && !participation.rows[0]) {
        throw new BadRequestException(
          "Нельзя сменить абонемент после списания занятия.",
        );
      }
    }

    // KVA-237: списание с абонемента по таблице правил (доля от типа
    // посещения), идемпотентно по дельте — смена статуса задним числом
    // пересчитывает уже списанные часы.
    for (const item of items) {
      await this.reconcileSubscriptionUsage(client, lessonId, item.studentId);
    }

    // «Уведомить об изменениях» (модалка HolliHop): in-app+push клиенту.
    await client.query(
      `
        update app.lessons
        set status = 'completed', updated_at = now()
        where id = $1 and deleted_at is null
      `,
      [lessonId],
    );
    });

    if (dto.notifyClient) {
      await this.notifyAttendanceChanged(lessonId, items.map((i) => i.studentId));
    }
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
  private async reconcileSubscriptionUsage(
    client: PoolClient,
    lessonId: string,
    studentId: string,
  ) {
    // Read-compute-write on charged_hours/lessons_used: runs inside one
    // transaction serialized by a per-participation advisory lock, otherwise a
    // double-submit (teacher retry) reads charged=0 twice and decrements the
    // subscription twice for one attended lesson.
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
        is_trial: boolean;
      }>(
        `
        select lp.attendance_kind, lp.charge_share, lp.charged_hours,
          lp.subscription_id,
          coalesce(l.duration_minutes, 60)::numeric / 60 as hours,
          l.is_trial
        from app.lesson_participation lp
        join app.lessons l on l.id = lp.lesson_id
        where lp.lesson_id = $1 and lp.student_id = $2
      `,
        [lessonId, studentId],
      );
      const row = state.rows[0];
      if (!row) return;
      const hours = Number(row.hours);
      // Trial attendance is historical evidence only. Even after conversion
      // rebinds the trial to a student, it must never consume their subscription.
      const target = row.is_trial
        ? 0
        : Math.round(
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
        const chargeResult = await client.query<{ id: string }>(
          `
          with pick as (
            select s.id
            from app.subscriptions s
            where s.id = $3::uuid
              and s.status = 'active'
              and (s.starts_at is null or s.starts_at <= current_date)
              and (s.expires_at is null or s.expires_at >= current_date)
              and s.lessons_used + $4::numeric <= s.lessons_total
            union all
            (
              select s.id
              from app.subscriptions s
              where $3::uuid is null
                and s.status = 'active'
                and (s.starts_at is null or s.starts_at <= current_date)
                and (s.expires_at is null or s.expires_at >= current_date)
                and s.lessons_used + $4::numeric <= s.lessons_total
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
            from pick
            where s.id = pick.id
              and s.lessons_used + $4::numeric <= s.lessons_total
            returning s.id
          )
          update app.lesson_participation lp
          set subscription_id = (select id from dec),
            charged_hours = $5::numeric
          where lp.lesson_id = $1 and lp.student_id = $2
            and exists (select 1 from dec)
          returning lp.id
        `,
          [lessonId, studentId, row.subscription_id, delta, target],
        );
        if (row.subscription_id && !chargeResult.rows[0]) {
          throw new BadRequestException(
            "Выбранный абонемент неактивен или в нём недостаточно занятий.",
          );
        }
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
  }

  /** KVA-237: пуш/in-app «изменение по занятию» клиентам с аккаунтами. */
  private async notifyAttendanceChanged(lessonId: string, studentIds: string[]) {
    if (!studentIds.length) return;
    const lesson = await this.database.query<{
      scheduled_at: Date | string;
    }>(
      `
        select scheduled_at
        from app.lessons
        where id = $1 and deleted_at is null
        limit 1
      `,
      [lessonId],
    );
    const scheduledAt = lesson.rows[0]?.scheduled_at;
    if (!scheduledAt) return;
    const audience = new Set<string>();
    for (const studentId of studentIds) {
      for (const userId of await audienceForStudent(this.database, studentId)) {
        audience.add(userId);
      }
    }
    const when = new Date(String(scheduledAt));
    const dateLabel = Number.isNaN(when.getTime())
      ? ""
      : ` ${when.toLocaleDateString("ru-RU", { day: "2-digit", month: "2-digit", timeZone: "Europe/Moscow" })}`;
    for (const userId of audience) {
      await this.notifications
        .notifyUser({
          userId,
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
