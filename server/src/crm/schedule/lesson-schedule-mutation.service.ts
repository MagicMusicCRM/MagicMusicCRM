import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from "@nestjs/common";
import { AuditEventInput, AuditService } from "../../audit/audit.service";
import {
  ActorContext,
  isManagerOrAdminRole,
} from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { NotificationsService } from "../../notifications/notifications.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { audienceForLesson } from "../audience";
import { CrmPolicy } from "../crm.policy";
import { UpsertLessonDto } from "../dto/upsert-lesson.dto";
import { LessonRow, formatLessonTimeMoscow, toLessonDto } from "../crm-mappers";
import { assertLessonPatchUsesTransition } from "./lesson-protected-patch.guard";
import { ScheduleConflictService } from "./schedule-conflict.service";
import { ScheduleSeriesMaterializerService } from "./schedule-series-materializer.service";
import { ScheduleQueryExecutor } from "./schedule-locks";

// Pre-update snapshot used by updateLesson to detect a genuine reschedule
// (time / room / teacher delta) and resolve the assigned teacher (KVA-158).
interface RescheduleSnapshotRow {
  student_id: string | null;
  lead_id: string | null;
  teacher_id: string | null;
  room_id: string | null;
  scheduled_at: Date | string | null;
  duration_minutes?: number | string | null;
  group_id?: string | null;
  is_trial: boolean;
  teacher_user_id: string | null;
}

@Injectable()
export class LessonScheduleMutationService {
  private readonly logger = new Logger(LessonScheduleMutationService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly notifications: NotificationsService,
    private readonly realtime: RealtimeBus,
    private readonly conflicts: ScheduleConflictService,
  ) {}

  private async notifyTrialBooked(
    lesson: LessonRow,
    affectedUserIds: string[],
  ): Promise<void> {
    if (!affectedUserIds.length) return;
    const whenLocal = formatLessonTimeMoscow(lesson.scheduled_at);
    await Promise.all(
      affectedUserIds.map((userId) =>
        this.notifications
          .notifyUser({
            userId,
            title: "Пробное занятие назначено",
            body: `Пробное занятие назначено на ${whenLocal} (по Москве). Подробности в приложении.`,
            data: {
              entityType: "lesson",
              entityId: lesson.id,
              eventType: "trial_lesson_booked",
            },
            channels: ["in_app", "push"],
          })
          .catch(() => undefined),
      ),
    );
  }

  private applyClientRef(dto: UpsertLessonDto): UpsertLessonDto {
    if (!dto.clientRef) return dto;
    const mapped: UpsertLessonDto = {
      ...dto,
      studentId: undefined,
      groupId: undefined,
      leadId: undefined,
      clientRef: undefined,
    };
    if (dto.clientRef.type === "lead") {
      mapped.leadId = dto.clientRef.id;
      mapped.studentId = undefined;
    } else {
      mapped.studentId = dto.clientRef.id;
      mapped.leadId = undefined;
    }
    return mapped;
  }

  private assertUnambiguousLessonSubject(
    dto: UpsertLessonDto,
    required: boolean,
  ): boolean {
    const selections = [
      dto.studentId != null,
      dto.groupId != null,
      dto.leadId != null,
    ].filter(Boolean).length;
    if (selections > 1) {
      throw new BadRequestException(
        "Для занятия можно выбрать только одного участника: ученика, группу или лида.",
      );
    }
    if (required && selections === 0) {
      throw new BadRequestException(
        "Укажите ученика, группу или лида для урока.",
      );
    }
    return selections === 1;
  }

  private assertLeadLessonIsTrial(
    leadId: string | null | undefined,
    isTrial: boolean | null | undefined,
  ): void {
    if (leadId && isTrial !== true) {
      throw new BadRequestException(
        "Занятие с лидом должно быть отмечено как пробное.",
      );
    }
  }

  async createLesson(actor: ActorContext, rawDto: UpsertLessonDto) {
    this.policy.assertCanWriteCrm(actor);
    this.assertCanSupplyTeacherCompensation(actor, rawDto);
    const dto = this.applyClientRef(rawDto);
    if (dto.force === true) {
      throw new BadRequestException(
        "Обход конфликтов расписания запрещён для всех ролей.",
      );
    }
    this.assertUnambiguousLessonSubject(dto, true);
    if (!dto.scheduledAt) {
      throw new BadRequestException("Дата урока обязательна.");
    }
    this.assertScheduledAtWithinBookingWindow(dto.scheduledAt);
    if (!dto.studentId && !dto.groupId && !dto.leadId) {
      throw new BadRequestException(
        "Укажите ученика, группу или лид для урока.",
      );
    }
    this.assertLeadLessonIsTrial(dto.leadId, dto.isTrial);
    const lesson = await this.database.transaction(async (client) => {
      const executor = client as unknown as ScheduleQueryExecutor;
      await this.assertLeadNotConverted(executor, dto.leadId);
      await this.conflicts.assertNoScheduleConflicts(
        {
          teacherId: dto.teacherId ?? null,
          roomId: dto.roomId ?? null,
          startsAt: dto.scheduledAt!,
          durationMinutes: dto.durationMinutes ?? 60,
          groupId: dto.groupId ?? null,
        },
        executor,
      );
      return this.insertLesson(executor, dto);
    });
    await this.recordAuditSafe({
      actor,
      action: "crm.lesson_created",
      entityType: "lesson",
      entityId: lesson.id,
    });
    let affectedUserIds: string[] = [];
    try {
      affectedUserIds = await audienceForLesson(this.database, lesson);
    } catch (error) {
      // The lesson insert has already committed. Audience resolution is a
      // best-effort side effect; surfacing its failure as 500 would invite a
      // retry that creates a duplicate trial lesson.
      this.logger.warn(
        `Lesson ${lesson.id} created but audience resolution failed: ${String(error)}`,
      );
    }
    this.realtime.emitCrmChanged({
      entity: "lesson",
      action: "created",
      id: lesson.id,
      branchId: lesson.branch_id ?? null,
      affectedUserIds,
    });
    if (lesson.is_trial) {
      await this.notifyTrialBooked(lesson, affectedUserIds);
    }
    return toLessonDto(lesson);
  }

  private async assertLeadNotConverted(
    executor: ScheduleQueryExecutor,
    leadId: string | null | undefined,
  ): Promise<void> {
    if (!leadId) return;
    const conversion = await executor.query<{ converted: boolean }>(
      `
        with locked_lead as (
          select pg_advisory_xact_lock(
            hashtextextended($1::uuid::text, 0)
          )
        )
        select exists (
          select 1
          from app.students student
          where student.lead_id = $1
            and student.deleted_at is null
        ) as converted
        from locked_lead
      `,
      [leadId],
    );
    if (conversion.rows[0]?.converted) {
      throw new ConflictException(
        "Лид уже стал учеником; назначьте обычное занятие ученику.",
      );
    }
  }

  private async insertLesson(
    executor: ScheduleQueryExecutor,
    dto: UpsertLessonDto,
  ): Promise<LessonRow> {
    const result = await executor.query<LessonRow>(
      `
        insert into app.lessons (
          student_id, group_id, lead_id, teacher_id, branch_id, room_id, scheduled_at, duration_minutes,
          status, is_trial, notes, teacher_rate
        )
        values ($1, $2, $3, $4, $5, $6, $7, coalesce($8, 60), coalesce($9, 'scheduled'), coalesce($10, false), $11, $12::numeric)
        returning id, student_id, group_id, lead_id, teacher_id, branch_id, room_id, scheduled_at, duration_minutes,
          status, is_trial, notes, teacher_rate, null::uuid as student_user_id, null::uuid as teacher_user_id,
          null::text as student_name, null::text as lead_name, null::text as teacher_name, null::text as branch_name,
          null::text as room_name, null::text as group_name, null::numeric as group_price_per_lesson
      `,
      [
        dto.studentId ?? null,
        dto.groupId ?? null,
        dto.leadId ?? null,
        dto.teacherId ?? null,
        dto.branchId ?? null,
        dto.roomId ?? null,
        dto.scheduledAt,
        dto.durationMinutes ?? null,
        dto.status ?? null,
        dto.isTrial ?? null,
        dto.notes?.trim() || null,
        dto.teacherRate ?? null,
      ],
    );
    return result.rows[0];
  }

  async updateLesson(
    actor: ActorContext,
    lessonId: string,
    rawDto: UpsertLessonDto,
  ) {
    this.assertCanSupplyTeacherCompensation(actor, rawDto);
    const dto = this.applyClientRef(rawDto);
    if (dto.status !== undefined) {
      throw new BadRequestException({
        code: "MANUAL_LESSON_LIFECYCLE_FORBIDDEN",
        message: "Lesson lifecycle is server-managed.",
        fields: ["status"],
      });
    }
    if (
      actor.role === "teacher" &&
      Object.keys(dto).some(
        (field) => !["expectedVersion", "notes"].includes(field),
      )
    ) {
      this.policy.assertCanWriteCrm(actor);
    }
    assertLessonPatchUsesTransition(dto);
    const result = await this.database.transaction(async (client) => {
      const before = await client.query<RescheduleSnapshotRow>(
        `
          select l.student_id, l.group_id, l.lead_id, l.teacher_id,
            l.room_id, l.scheduled_at, l.duration_minutes, l.is_trial,
            tp.user_id as teacher_user_id
          from app.lessons l
          left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
          left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
          where l.id = $1 and l.deleted_at is null
          limit 1
          for update of l
        `,
        [lessonId],
      );
      await this.assertCanUpdateLesson(
        actor,
        lessonId,
        dto,
        before.rows[0] ?? null,
      );
      return client.query<LessonRow>(
        `
          update app.lessons
          set notes = $2, updated_at = now()
          where id = $1 and deleted_at is null
          returning id, student_id, group_id, lead_id, teacher_id, branch_id,
            room_id, scheduled_at, duration_minutes, status, is_trial, notes,
            teacher_rate, null::uuid as student_user_id,
            null::uuid as teacher_user_id, null::text as student_name,
            null::text as lead_name, null::text as teacher_name,
            null::text as branch_name, null::text as room_name,
            null::text as group_name, null::numeric as group_price_per_lesson
        `,
        [lessonId, dto.notes!.trim() || null],
      );
    });
    const lesson = result.rows[0];
    if (!lesson) throw new NotFoundException("Урок не найден.");
    await this.recordAuditSafe({
      actor,
      action: "crm.lesson_updated",
      entityType: "lesson",
      entityId: lesson.id,
    });
    const affectedUserIds = await audienceForLesson(this.database, lesson);
    this.realtime.emitCrmChanged({
      entity: "lesson",
      action: "updated",
      id: lesson.id,
      branchId: lesson.branch_id ?? null,
      affectedUserIds,
    });
    return toLessonDto(lesson);
  }

  private assertCanSupplyTeacherCompensation(
    actor: ActorContext,
    dto: UpsertLessonDto,
  ): void {
    this.policy.assertCanSupplyTeacherCompensation(actor, {
      teacherRate: dto.teacherRate,
      teacherCompensationType: dto.teacherCompensationType,
      teacherCompensationValue: dto.teacherCompensationValue,
      financialDecision: {
        teacherCompensationRuleKey:
          dto.financialDecision?.teacherCompensationRuleKey,
        teacherCompensationValueMinor:
          dto.financialDecision?.teacherCompensationValueMinor,
      },
    });
  }

  /**
   * Client self-view: upcoming lessons across the caller's own students (direct
   * and via group membership), used by CrmService.getMySummary. Un-gated by
   * CrmPolicy — ownership is established upstream. Owns the lesson SQL that
   * previously lived inline in CrmService.
   */
  async deleteLesson(actor: ActorContext, lessonId: string) {
    // Only managers/admins may delete a lesson outright; teachers can update
    // status/notes via updateLesson but not remove a lesson from the schedule.
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<LessonRow>(
      `
        update app.lessons
        set deleted_at = now(), updated_at = now()
        where id = $1 and deleted_at is null
        returning id, student_id, group_id, lead_id, teacher_id, branch_id,
          room_id, scheduled_at, duration_minutes, status, is_trial, notes,
          null::uuid as student_user_id, null::uuid as teacher_user_id,
          null::text as student_name, null::text as lead_name,
          null::text as teacher_name,
          null::text as branch_name, null::text as room_name,
          null::text as group_name, null::numeric as group_price_per_lesson
      `,
      [lessonId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Урок не найден.");
    // Drop any pending reminder markers for the removed lesson.
    await this.database.query(
      "delete from app.lesson_reminders where lesson_id = $1",
      [lessonId],
    );
    await this.recordAuditSafe({
      actor,
      action: "crm.lesson_deleted",
      entityType: "lesson",
      entityId: row.id,
    });
    const affectedUserIds = await audienceForLesson(this.database, row);
    this.realtime.emitCrmChanged({
      entity: "lesson",
      action: "deleted",
      id: row.id,
      branchId: row.branch_id ?? null,
      affectedUserIds,
    });
    return { success: true };
  }

  private async assertCanUpdateLesson(
    actor: ActorContext,
    lessonId: string,
    dto: UpsertLessonDto,
    lockedSnapshot?: RescheduleSnapshotRow | null,
  ) {
    if (isManagerOrAdminRole(actor.role)) return;
    if (actor.role !== "teacher") {
      this.policy.assertCanWriteCrm(actor);
      return;
    }

    if (this.hasRestrictedTeacherFields(dto)) {
      this.policy.assertCanWriteCrm(actor);
      return;
    }

    const teacherUserId = await this.resolveLessonTeacherUserId(
      lessonId,
      lockedSnapshot,
    );
    if (teacherUserId === actor.userId) return;
    throw new NotFoundException("Урок не найден.");
  }

  private hasRestrictedTeacherFields(dto: UpsertLessonDto): boolean {
    // teacherRate is what the school pays the teacher. Treating it as an
    // unrestricted self-edit would allow a teacher to grant their own raise.
    return [
      dto.studentId,
      dto.groupId,
      dto.leadId,
      dto.teacherId,
      dto.branchId,
      dto.roomId,
      dto.scheduledAt,
      dto.durationMinutes,
      dto.teacherRate,
      dto.isTrial,
    ].some((value) => value !== undefined);
  }

  private async resolveLessonTeacherUserId(
    lessonId: string,
    lockedSnapshot?: RescheduleSnapshotRow | null,
  ): Promise<string | null> {
    if (lockedSnapshot !== undefined) {
      return lockedSnapshot?.teacher_user_id ?? null;
    }
    const result = await this.database.query<{
      teacher_user_id: string | null;
    }>(
      `
        select tp.user_id as teacher_user_id
        from app.lessons l
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where l.id = $1 and l.deleted_at is null
        limit 1
      `,
      [lessonId],
    );
    return result.rows[0]?.teacher_user_id ?? null;
  }


  private assertScheduledAtWithinBookingWindow(value: string): void {
    const scheduledAt = new Date(value);
    const upperBound =
      Date.now() +
      (ScheduleSeriesMaterializerService.MAX_BOOKING_AHEAD_DAYS + 1) *
        24 *
        60 *
        60 *
        1000;
    if (
      !Number.isFinite(scheduledAt.getTime()) ||
      scheduledAt.getTime() > upperBound
    ) {
      throw new BadRequestException(
        `Lesson cannot be scheduled more than ${ScheduleSeriesMaterializerService.MAX_BOOKING_AHEAD_DAYS} days ahead.`,
      );
    }
  }

  private async recordAuditSafe(event: AuditEventInput): Promise<void> {
    try {
      await this.audit.record(event);
    } catch (error) {
      // Schedule writes have already committed when this helper is called.
      // Do not return a false 5xx that makes clients retry a persisted lesson.
      this.logger.error(
        `Audit write failed for ${event.action}/${event.entityId ?? "batch"}: ${String(error)}`,
      );
    }
  }
}
