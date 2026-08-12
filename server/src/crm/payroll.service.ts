import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { assertVersionedMutationMetadata } from "../platform/versioned-mutation-metadata";
import { CreateTeacherPayoutDto } from "./dto/create-teacher-payout.dto";
import { SetTeacherRateDto } from "./dto/set-teacher-rate.dto";
import {
  DeleteTeacherPayrollEntryDto,
  UpdateTeacherPayoutEntryDto,
  UpdateTeacherRateEntryDto,
} from "./dto/manage-teacher-payroll-entry.dto";
import { TeacherStatsQuery } from "./dto/teacher-stats.query";
import { CrmPolicy } from "./crm.policy";
import { trimOptional } from "./crm-util";

/**
 * Вид учебной единицы в отчёте «Статистика преподавателей».
 *
 * ✔ Решение владельца 17.07: «индивидуальный пробный» — это обычное занятие с
 * пометкой «пробное», а не отдельный тип занятия. Но в отчёте он **свой
 * разрез**: раньше `trial` схлопывал все негрупповые пробные, и хуже — пробные
 * РАЗНЫХ лидов сходились в одну строку «Пробное занятие», потому что ключом
 * был `student_id`, а у пробного его нет.
 */
export type TeacherStatsUnitType =
  "group" | "individual" | "group_trial" | "individual_trial";

/** Проведённое занятие для расчёта начисления (проекция, не материализуется). */
interface PayrollLessonRow {
  id: string;
  teacher_id: string;
  student_id: string | null;
  /** Пробное занятие вешается на лида — ученика у него ещё нет. */
  lead_id: string | null;
  group_id: string | null;
  group_name: string | null;
  student_name: string | null;
  lead_name: string | null;
  scheduled_at: Date | string;
  duration_minutes: number | string;
  is_trial: boolean;
  group_rate: string | number | null;
  teacher_rate: string | number | null;
  attendance_kind: string | null;
  charge_share: string | number | null;
  settlement_fact_id: string | null;
  settled_amount_minor: string | number | null;
}

interface TeacherRateRow {
  id?: string;
  teacher_id: string;
  rate: string | number;
  effective_from: Date | string;
  created_at?: Date | string;
  author_first_name?: string | null;
  author_last_name?: string | null;
}

export interface TeacherRateEntry {
  id: string | null;
  rate: number;
  effectiveFrom: string;
  createdAt: Date | string | null;
  authorName: string | null;
}

interface TeacherPayoutRow {
  id: string;
  teacher_id: string;
  amount: string | number;
  kind: string;
  comment: string | null;
  paid_at: Date | string;
  author_first_name?: string | null;
  author_last_name?: string | null;
}

/**
 * KVA-238 зарплатный модуль педагогов, extracted from CrmService (SRP): payroll
 * summary, payouts/bonuses/deductions, teacher rate history, and the teacher
 * stats report. Начисления НЕ материализуются — это проекция по проведённым
 * занятиям (паттерн ledger из KVA-235). Touches app.teacher_payouts /
 * app.teacher_rates / app.lessons and the shared database/audit/policy
 * collaborators. No internal callers.
 */
@Injectable()
export class PayrollService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
  ) {}

  /** Дата в формате yyyy-mm-dd без сдвига часового пояса для date-колонок PG. */
  private toDateOnly(value: Date | string): string {
    if (value instanceof Date) {
      const y = value.getFullYear();
      const m = String(value.getMonth() + 1).padStart(2, "0");
      const d = String(value.getDate()).padStart(2, "0");
      return `${y}-${m}-${d}`;
    }
    return String(value).slice(0, 10);
  }

  private round2(value: number): number {
    return Math.round(value * 100) / 100;
  }

  /**
   * Эффективная ставка и коэффициент занятия.
   * Ставка: поурочная ставка (lessons.teacher_rate, набирается вручную) ??
   * переопределение группы (groups.teacher_rate) ?? последняя ставка педагога
   * с effective_from <= даты занятия ?? 0 (0 = «входит в оклад»).
   * Коэффициент (KVA-237, lesson_participation.attendance_kind): unpaid_miss →
   * 0, partially_paid → charge_share, прочие статусы, занятия без
   * participation и групповые занятия → 1.
   */
  private computeLessonAccrual(
    lesson: PayrollLessonRow,
    ratesByTeacher: Map<string, TeacherRateEntry[]>,
  ): { hours: number; rate: number; coefficient: number; amount: number } {
    const hours = Number(lesson.duration_minutes ?? 0) / 60;
    if (
      lesson.settlement_fact_id != null &&
      lesson.settled_amount_minor != null
    ) {
      const amount = Number(lesson.settled_amount_minor) / 100;
      return {
        hours,
        rate: hours > 0 ? this.round2(amount / hours) : 0,
        coefficient: 1,
        amount: this.round2(amount),
      };
    }
    let rate: number;
    if (lesson.teacher_rate !== null && lesson.teacher_rate !== undefined) {
      // Per-lesson override (набранная вручную ставка за это занятие) wins.
      rate = Number(lesson.teacher_rate);
    } else if (lesson.group_rate !== null && lesson.group_rate !== undefined) {
      rate = Number(lesson.group_rate);
    } else {
      const lessonDate = this.toDateOnly(lesson.scheduled_at);
      // История отсортирована по effective_from по возрастанию — берём
      // последнюю запись, начавшую действовать не позже даты занятия.
      let effective = 0;
      for (const entry of ratesByTeacher.get(lesson.teacher_id) ?? []) {
        if (entry.effectiveFrom <= lessonDate) effective = entry.rate;
        else break;
      }
      rate = effective;
    }
    let coefficient = 1;
    if (lesson.student_id && lesson.attendance_kind === "unpaid_miss") {
      coefficient = 0;
    } else if (
      lesson.student_id &&
      lesson.attendance_kind === "partially_paid"
    ) {
      coefficient = Number(lesson.charge_share ?? 1);
    }
    return {
      hours,
      rate,
      coefficient,
      // Round each lesson to kopecks BEFORE the callers sum: non-round
      // durations (50 min = 0.8333…h) leave binary-float residue that
      // accumulates across a month of lessons if only the total is rounded.
      amount: Math.round(hours * rate * coefficient * 100) / 100,
    };
  }

  /** Проведённые занятия педагога(ов) для проекции начислений. */
  private async loadPayrollLessons(filters: {
    teacherId?: string | null;
    branchId?: string | null;
    from?: string | null;
    to?: string | null;
  }): Promise<PayrollLessonRow[]> {
    // ponytail: без пагинации — проекция за период/по педагогу, объёмы школы
    // (сотни строк). При росте добавить помесячный материализованный снапшот.
    const result = await this.database.query<PayrollLessonRow>(
      `
        select l.id, l.teacher_id, l.student_id, l.lead_id, l.group_id,
          l.scheduled_at, l.duration_minutes, l.is_trial,
          l.teacher_rate, g.teacher_rate as group_rate, g.name as group_name,
          trim(coalesce(sp.first_name, '') || ' ' || coalesce(sp.last_name, '')) as student_name,
          trim(coalesce(ld.first_name, '') || ' ' || coalesce(ld.last_name, '')) as lead_name,
          lp.attendance_kind, lp.charge_share,
          compensation.id as settlement_fact_id,
          compensation.amount_minor as settled_amount_minor
        from app.lessons l
        left join app.groups g on g.id = l.group_id and g.deleted_at is null
        left join app.students s on s.id = l.student_id and s.deleted_at is null
        left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
        -- Пробное занятие висит на лиде: без него все пробные разных людей
        -- сходились в одну безымянную строку отчёта.
        left join app.leads ld on ld.id = l.lead_id and ld.deleted_at is null
        left join app.lesson_participation lp
          on lp.lesson_id = l.id and lp.student_id = l.student_id
        left join app.lesson_teacher_compensation_facts_effective compensation
          on compensation.lesson_id = l.id
        where l.deleted_at is null
          and l.teacher_id is not null
          and l.status in ('completed', 'done')
          and ($1::uuid is null or l.teacher_id = $1)
          and ($2::uuid is null or l.branch_id = $2)
          and ($3::timestamptz is null or l.scheduled_at >= $3::timestamptz)
          and ($4::timestamptz is null or l.scheduled_at < $4::timestamptz)
        order by l.scheduled_at asc, l.id asc
      `,
      [
        filters.teacherId ?? null,
        filters.branchId ?? null,
        filters.from ?? null,
        filters.to ?? null,
      ],
    );
    return result.rows;
  }

  /**
   * Вид учебной единицы. Пробность — отдельная ось от «группа/индивидуально»:
   * пробное занятие бывает и групповым.
   */
  private unitTypeFor(lesson: PayrollLessonRow): TeacherStatsUnitType {
    if (lesson.group_id) return lesson.is_trial ? "group_trial" : "group";
    return lesson.is_trial ? "individual_trial" : "individual";
  }

  /**
   * Ключ учебной единицы.
   *
   * Пробные отделены от обычных, а не подмешаны к ним: иначе ученик, у которого
   * было пробное, а потом начались занятия, показывал бы пробное как обычное —
   * и обратно, пробные часы исчезали бы из своего разреза.
   *
   * Пробное ключуется по лиду (`lead_id`), у которого оно и висит. Раньше ключ
   * был `s:${student_id ?? "trial"}`, а у пробного `student_id` пуст — поэтому
   * ВСЕ пробные педагога за период сходились в одну строку.
   */
  private unitKeyFor(lesson: PayrollLessonRow): string {
    if (lesson.group_id) {
      return lesson.is_trial ? `gt:${lesson.group_id}` : `g:${lesson.group_id}`;
    }
    if (!lesson.is_trial) return `s:${lesson.student_id ?? "unknown"}`;
    // Пробное: сначала лид, потом ученик (пробное можно назначить и ему).
    const subject = lesson.lead_id ?? lesson.student_id;
    // `t:unknown` — занятие без лида и без ученика: данные битые, но
    // сваливать его в чужую строку хуже, чем показать отдельной.
    return `t:${subject ?? "unknown"}`;
  }

  private unitNameFor(lesson: PayrollLessonRow): string {
    if (lesson.group_id) return lesson.group_name ?? "Группа";
    const person =
      lesson.student_name?.trim() || lesson.lead_name?.trim() || "";
    if (person) return person;
    return lesson.is_trial ? "Пробное занятие" : "Без имени";
  }

  /** История ставок педагогов, отсортированная по effective_from. */
  private async loadTeacherRates(
    teacherIds: string[],
  ): Promise<Map<string, TeacherRateEntry[]>> {
    const map = new Map<string, TeacherRateEntry[]>();
    if (!teacherIds.length) return map;
    const result = await this.database.query<TeacherRateRow>(
      `
        select tr.id, tr.teacher_id, tr.rate, tr.effective_from, tr.created_at,
          author.first_name as author_first_name,
          author.last_name as author_last_name
        from app.teacher_rates tr
        left join app.users u on u.id = tr.created_by and u.deleted_at is null
        left join app.profiles author
          on author.user_id = u.id and author.deleted_at is null
        where tr.teacher_id = any($1::uuid[])
          and tr.deleted_at is null
        order by tr.teacher_id, tr.effective_from asc, tr.created_at asc, tr.id asc
      `,
      [teacherIds],
    );
    for (const row of result.rows) {
      const list = map.get(row.teacher_id) ?? [];
      list.push({
        id: row.id ?? null,
        rate: Number(row.rate),
        effectiveFrom: this.toDateOnly(row.effective_from),
        createdAt: row.created_at ?? null,
        authorName:
          [row.author_first_name, row.author_last_name]
            .filter(Boolean)
            .join(" ") || null,
      });
      map.set(row.teacher_id, list);
    }
    return map;
  }

  /**
   * Сводка по зарплате педагога: начислено/выплачено/задолженность + история
   * ставок и список выплат. Задолженность = начислено + доплаты (bonus) −
   * вычеты (deduction) − выплачено (payout).
   */
  async getTeacherPayroll(actor: ActorContext, teacherId: string) {
    this.policy.assertCanReadPayroll(actor);
    const header = await this.database.query<{
      id: string;
      version: string | number;
    }>(
      `
        select t.id, coalesce(aggregate.version, 0) as version
        from app.teachers t
        left join app.aggregate_versions aggregate
          on aggregate.aggregate_type = 'teacher:payroll'
          and aggregate.aggregate_id = t.id::text
        where t.id = $1 and t.deleted_at is null
      `,
      [teacherId],
    );
    if (!header.rows[0]) {
      throw new NotFoundException("Преподаватель не найден.");
    }
    const lessons = await this.loadPayrollLessons({ teacherId });
    const rates = await this.loadTeacherRates([teacherId]);
    let accruedTotal = 0;
    let hoursTotal = 0;
    let payableLessons = 0;
    for (const lesson of lessons) {
      const { hours, amount } = this.computeLessonAccrual(lesson, rates);
      hoursTotal += hours;
      accruedTotal += amount;
      if (amount > 0) payableLessons += 1;
    }
    const payoutsResult = await this.database.query<TeacherPayoutRow>(
      `
        select tp.id, tp.teacher_id, tp.amount, tp.kind, tp.comment, tp.paid_at,
          author.first_name as author_first_name,
          author.last_name as author_last_name
        from app.teacher_payouts tp
        left join app.users u on u.id = tp.created_by and u.deleted_at is null
        left join app.profiles author on author.user_id = u.id and author.deleted_at is null
        where tp.deleted_at is null and tp.teacher_id = $1
        order by tp.paid_at desc, tp.id desc
      `,
      [teacherId],
    );
    let paidTotal = 0;
    let bonusTotal = 0;
    let deductionTotal = 0;
    for (const row of payoutsResult.rows) {
      const amount = Number(row.amount);
      if (row.kind === "payout") paidTotal += amount;
      else if (row.kind === "bonus") bonusTotal += amount;
      else deductionTotal += amount;
    }
    const rateHistory = rates.get(teacherId) ?? [];
    const today = this.toDateOnly(new Date());
    let currentRate: number | null = null;
    for (const entry of rateHistory) {
      if (entry.effectiveFrom <= today) currentRate = entry.rate;
      else break;
    }
    return {
      teacherId,
      version: Number(header.rows[0].version),
      hoursTotal: this.round2(hoursTotal),
      completedLessons: lessons.length,
      payableLessons,
      noAccrualLessons: lessons.length - payableLessons,
      accruedTotal: this.round2(accruedTotal),
      bonusTotal: this.round2(bonusTotal),
      deductionTotal: this.round2(deductionTotal),
      paidTotal: this.round2(paidTotal),
      debt: this.round2(accruedTotal + bonusTotal - deductionTotal - paidTotal),
      currentRate,
      rateHistory,
      payouts: payoutsResult.rows.map((row) => ({
        id: row.id,
        kind: row.kind,
        amount: Number(row.amount),
        comment: row.comment,
        paidAt: row.paid_at,
        authorName:
          [row.author_first_name, row.author_last_name]
            .filter(Boolean)
            .join(" ") || null,
      })),
    };
  }

  /** KVA-238: выплата/доплата/вычет преподавателю. */
  async createTeacherPayout(
    actor: ActorContext,
    teacherId: string,
    dto: CreateTeacherPayoutDto,
    metadata: { idempotencyKey: string; requestId: string },
  ) {
    this.policy.assertCanReadPayroll(actor);
    assertVersionedMutationMetadata(metadata);
    const reasonText = dto.reasonText.trim();
    if (!reasonText) {
      throw new BadRequestException("Укажите причину операции.");
    }
    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "crm.teacher-payout.create",
      idempotencyKey: metadata.idempotencyKey,
      payload: {
        teacherId,
        kind: dto.kind,
        amount: dto.amount,
        comment: trimOptional(dto.comment),
        paidAt: dto.paidAt ?? null,
        reasonText,
      },
      aggregateType: "teacher:payroll",
      aggregateId: teacherId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      authorization: {
        actor,
        capabilityKey: "commerce.teacher_payroll.write",
      },
      audit: {
        action: "crm.teacher_payout_created",
        entityType: "teacher",
        entityId: teacherId,
        reason: "TEACHER_PAYOUT",
        reasonText,
        metadata: { kind: dto.kind },
      },
      outbox: {
        type: "crm.teacher_payroll.changed",
        payload: { action: dto.kind, entityId: teacherId },
      },
      mutate: async (client) => {
        const teacher = await client.query<{ id: string }>(
          `select id from app.teachers where id = $1 and deleted_at is null`,
          [teacherId],
        );
        if (!teacher.rows[0]) {
          throw new NotFoundException("Преподаватель не найден.");
        }
        const inserted = await client.query<{ id: string }>(
          `
            insert into app.teacher_payouts
              (teacher_id, amount, kind, comment, paid_at, created_by)
            values ($1, $2, $3, $4, coalesce($5::timestamptz, now()), $6)
            returning id
          `,
          [
            teacherId,
            dto.amount,
            dto.kind,
            trimOptional(dto.comment),
            dto.paidAt ?? null,
            actor.userId,
          ],
        );
        return { payoutId: inserted.rows[0].id };
      },
    });
    const payoutResult = await this.database.query<TeacherPayoutRow>(
      `
        select id, teacher_id, amount, kind, comment, paid_at
        from app.teacher_payouts
        where id = $1 and deleted_at is null
      `,
      [String(result.resultRef.payoutId)],
    );
    const payout = payoutResult.rows[0];
    if (!payout) {
      throw new NotFoundException("Выплата преподавателю не найдена.");
    }
    return {
      id: payout.id,
      teacherId: payout.teacher_id,
      kind: payout.kind,
      amount: Number(payout.amount),
      comment: payout.comment,
      paidAt: payout.paid_at,
      version: result.version,
      replayed: result.replayed,
    };
  }

  /** KVA-238: новая ставка педагога (история сохраняется, 0 = «входит в оклад»). */
  async setTeacherRate(
    actor: ActorContext,
    teacherId: string,
    dto: SetTeacherRateDto,
    metadata: { idempotencyKey: string; requestId: string },
  ) {
    this.policy.assertCanReadPayroll(actor);
    assertVersionedMutationMetadata(metadata);
    const reasonText = dto.reasonText.trim();
    if (!reasonText) {
      throw new BadRequestException("Укажите причину изменения ставки.");
    }
    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "crm.teacher-rate.create",
      idempotencyKey: metadata.idempotencyKey,
      payload: {
        teacherId,
        rate: dto.rate,
        effectiveFrom: dto.effectiveFrom ?? null,
        reasonText,
      },
      aggregateType: "teacher:payroll",
      aggregateId: teacherId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      authorization: {
        actor,
        capabilityKey: "commerce.teacher_payroll.write",
      },
      audit: {
        action: "crm.teacher_rate_set",
        entityType: "teacher",
        entityId: teacherId,
        reason: "TEACHER_RATE_CHANGE",
        reasonText,
      },
      outbox: {
        type: "crm.teacher_payroll.changed",
        payload: { action: "rate_changed", entityId: teacherId },
      },
      mutate: async (client) => {
        const teacher = await client.query<{ id: string }>(
          `select id from app.teachers where id = $1 and deleted_at is null`,
          [teacherId],
        );
        if (!teacher.rows[0]) {
          throw new NotFoundException("Преподаватель не найден.");
        }
        const inserted = await client.query<{ id: string }>(
          `
            insert into app.teacher_rates (
              teacher_id, rate, effective_from, created_by, created_at
            )
            values (
              $1, $2, coalesce($3::date, current_date), $4, clock_timestamp()
            )
            returning id
          `,
          [teacherId, dto.rate, dto.effectiveFrom ?? null, actor.userId],
        );
        return { entryId: inserted.rows[0].id };
      },
    });
    const rateResult = await this.database.query<TeacherRateRow>(
      `
        select id, teacher_id, rate, effective_from, created_at
        from app.teacher_rates
        where id = $1
      `,
      [String(result.resultRef.entryId)],
    );
    const rate = rateResult.rows[0];
    if (!rate) {
      throw new NotFoundException("Запись ставки преподавателя не найдена.");
    }
    return {
      id: rate.id,
      teacherId: rate.teacher_id,
      rate: Number(rate.rate),
      effectiveFrom: this.toDateOnly(rate.effective_from),
      version: result.version,
      replayed: result.replayed,
    };
  }

  async updateTeacherRate(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: UpdateTeacherRateEntryDto,
    metadata: { idempotencyKey: string; requestId: string },
  ) {
    this.policy.assertCanManagePayrollHistory(actor);
    assertVersionedMutationMetadata(metadata);
    const reasonText = dto.reasonText.trim();
    if (!reasonText) {
      throw new BadRequestException("Укажите причину исправления ставки.");
    }
    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "crm.teacher-rate.update",
      idempotencyKey: metadata.idempotencyKey,
      payload: {
        teacherId,
        entryId,
        rate: dto.rate,
        effectiveFrom: dto.effectiveFrom,
        reasonText,
      },
      aggregateType: "teacher:payroll",
      aggregateId: teacherId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      authorization: {
        actor,
        capabilityKey: "commerce.teacher_payroll.write",
      },
      audit: {
        action: "crm.teacher_rate_updated",
        entityType: "teacher",
        entityId: teacherId,
        reason: "TEACHER_RATE_CORRECTION",
        reasonText,
        beforeRef: { entryId },
      },
      outbox: {
        type: "crm.teacher_payroll.changed",
        payload: { action: "rate_updated", entityId: teacherId, entryId },
      },
      mutate: async (client) => {
        const updated = await client.query<{ id: string }>(
          `update app.teacher_rates
           set rate = $3, effective_from = $4::date,
             updated_at = clock_timestamp(), updated_by = $5
           where id = $1 and teacher_id = $2 and deleted_at is null
           returning id`,
          [entryId, teacherId, dto.rate, dto.effectiveFrom, actor.userId],
        );
        if (!updated.rows[0]) {
          throw new NotFoundException("Запись ставки преподавателя не найдена.");
        }
        return { entryId };
      },
    });
    return {
      id: entryId,
      teacherId,
      rate: dto.rate,
      effectiveFrom: dto.effectiveFrom,
      version: result.version,
      replayed: result.replayed,
    };
  }

  async deleteTeacherRate(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: DeleteTeacherPayrollEntryDto,
    metadata: { idempotencyKey: string; requestId: string },
  ) {
    this.policy.assertCanManagePayrollHistory(actor);
    return this.voidPayrollEntry(
      actor,
      teacherId,
      entryId,
      dto,
      metadata,
      "rate",
    );
  }

  async updateTeacherPayout(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: UpdateTeacherPayoutEntryDto,
    metadata: { idempotencyKey: string; requestId: string },
  ) {
    this.policy.assertCanManagePayrollHistory(actor);
    assertVersionedMutationMetadata(metadata);
    const reasonText = dto.reasonText.trim();
    if (!reasonText) {
      throw new BadRequestException("Укажите причину исправления выплаты.");
    }
    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "crm.teacher-payout.update",
      idempotencyKey: metadata.idempotencyKey,
      payload: {
        teacherId,
        entryId,
        kind: dto.kind,
        amount: dto.amount,
        comment: trimOptional(dto.comment),
        paidAt: dto.paidAt,
        reasonText,
      },
      aggregateType: "teacher:payroll",
      aggregateId: teacherId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      authorization: {
        actor,
        capabilityKey: "commerce.teacher_payroll.write",
      },
      audit: {
        action: "crm.teacher_payout_updated",
        entityType: "teacher",
        entityId: teacherId,
        reason: "TEACHER_PAYOUT_CORRECTION",
        reasonText,
        beforeRef: { entryId },
      },
      outbox: {
        type: "crm.teacher_payroll.changed",
        payload: { action: "payout_updated", entityId: teacherId, entryId },
      },
      mutate: async (client) => {
        const updated = await client.query<{ id: string }>(
          `update app.teacher_payouts
           set kind = $3, amount = $4, comment = $5,
             paid_at = $6::timestamptz, updated_at = clock_timestamp(),
             updated_by = $7
           where id = $1 and teacher_id = $2 and deleted_at is null
           returning id`,
          [
            entryId,
            teacherId,
            dto.kind,
            dto.amount,
            trimOptional(dto.comment),
            dto.paidAt,
            actor.userId,
          ],
        );
        if (!updated.rows[0]) {
          throw new NotFoundException("Выплата преподавателю не найдена.");
        }
        return { entryId };
      },
    });
    return {
      id: entryId,
      teacherId,
      kind: dto.kind,
      amount: dto.amount,
      comment: trimOptional(dto.comment),
      paidAt: dto.paidAt,
      version: result.version,
      replayed: result.replayed,
    };
  }

  async deleteTeacherPayout(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: DeleteTeacherPayrollEntryDto,
    metadata: { idempotencyKey: string; requestId: string },
  ) {
    this.policy.assertCanManagePayrollHistory(actor);
    return this.voidPayrollEntry(
      actor,
      teacherId,
      entryId,
      dto,
      metadata,
      "payout",
    );
  }

  private async voidPayrollEntry(
    actor: ActorContext,
    teacherId: string,
    entryId: string,
    dto: DeleteTeacherPayrollEntryDto,
    metadata: { idempotencyKey: string; requestId: string },
    kind: "rate" | "payout",
  ) {
    assertVersionedMutationMetadata(metadata);
    const reasonText = dto.reasonText.trim();
    if (!reasonText) {
      throw new BadRequestException("Укажите причину удаления записи.");
    }
    const table = kind === "rate" ? "teacher_rates" : "teacher_payouts";
    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: `crm.teacher-${kind}.delete`,
      idempotencyKey: metadata.idempotencyKey,
      payload: { teacherId, entryId, reasonText },
      aggregateType: "teacher:payroll",
      aggregateId: teacherId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      authorization: {
        actor,
        capabilityKey: "commerce.teacher_payroll.write",
      },
      audit: {
        action: `crm.teacher_${kind}_deleted`,
        entityType: "teacher",
        entityId: teacherId,
        reason: kind === "rate" ? "TEACHER_RATE_DELETE" : "TEACHER_PAYOUT_DELETE",
        reasonText,
        beforeRef: { entryId },
      },
      outbox: {
        type: "crm.teacher_payroll.changed",
        payload: { action: `${kind}_deleted`, entityId: teacherId, entryId },
      },
      mutate: async (client) => {
        const deleted = await client.query<{ id: string }>(
          `update app.${table}
           set deleted_at = clock_timestamp(), deleted_by = $3,
             updated_at = clock_timestamp(), updated_by = $3
           where id = $1 and teacher_id = $2 and deleted_at is null
           returning id`,
          [entryId, teacherId, actor.userId],
        );
        if (!deleted.rows[0]) {
          throw new NotFoundException(
            kind === "rate"
              ? "Запись ставки преподавателя не найдена."
              : "Выплата преподавателю не найдена.",
          );
        }
        return { entryId };
      },
    });
    return {
      id: entryId,
      teacherId,
      deleted: true,
      version: result.version,
      replayed: result.replayed,
    };
  }

  /**
   * KVA-238: отчёт «Статистика преподавателей». Учебная единица — группа или
   * индивидуальный ученик; trial — пробные занятия (lessons.is_trial).
   * По каждой единице: дни (дата + часы), часы всего, ставка за астр. час,
   * начислено; по педагогу — итоги и выплачено (payout) за период.
   */
  async getTeacherStatsReport(actor: ActorContext, query: TeacherStatsQuery) {
    this.policy.assertCanReadPayroll(actor);
    // Период по умолчанию — текущий месяц (процесс заказчика: закрытие месяца).
    const now = new Date();
    const from =
      query.from ??
      new Date(
        Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
      ).toISOString();
    const fromDate = new Date(from);
    const to =
      query.to ??
      new Date(
        Date.UTC(fromDate.getUTCFullYear(), fromDate.getUTCMonth() + 1, 1),
      ).toISOString();
    if (new Date(from).getTime() >= new Date(to).getTime()) {
      throw new BadRequestException(
        "Начало периода должно быть раньше окончания.",
      );
    }
    const lessons = (
      await this.loadPayrollLessons({
        teacherId: query.teacherId,
        branchId: query.branchId,
        from,
        to,
      })
    ).filter((lesson) => {
      if (!query.unitType) return true;
      // `trial` — любое пробное, групповое или нет. Оставлен как есть: это
      // разрез, которым уже пользуются, и сузить его молча значило бы менять
      // цифры под теми, кто на него смотрит.
      if (query.unitType === "trial") return lesson.is_trial;
      return this.unitTypeFor(lesson) === query.unitType;
    });
    const lessonTeacherIds = [...new Set(lessons.map((l) => l.teacher_id))];
    const rates = await this.loadTeacherRates(lessonTeacherIds);
    // The report must not lose a teacher who only has a payout/bonus/deduction
    // in the period. For a branch or unit slice such a movement cannot be
    // attributed safely, so movement-only rows are included only school-wide.
    const namesResult = await this.database.query<{
      id: string;
      name: string;
      salary: string | number | null;
    }>(
      `
        select t.id, t.salary,
          trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')) as name
        from app.teachers t
        left join app.profiles p on p.id = t.profile_id and p.deleted_at is null
        where t.deleted_at is null
          and ($1::uuid is null or t.id = $1)
          and (
            t.id = any($2::uuid[])
            or (
              $3::boolean
              and exists (
                select 1
                from app.teacher_payouts movement
                where movement.teacher_id = t.id
                  and movement.deleted_at is null
                  and movement.paid_at >= $4::timestamptz
                  and movement.paid_at < $5::timestamptz
              )
            )
          )
          and ($6::text is null or t.status = $6)
          and (
            $7::text is null
            or exists (
              select 1
              from app.teacher_disciplines td
              join app.disciplines d
                on d.id = td.discipline_id and d.deleted_at is null
              where td.teacher_id = t.id and lower(d.name) = lower($7)
            )
            -- Legacy rows carry the discipline as free text instead of the m2m.
            or lower(coalesce(t.specialization, '')) like '%' || lower($7) || '%'
          )
          and (
            $8::text is null
            or lower(
              coalesce(t.custom_data->>'categories', t.custom_data->>'category', '')
            ) like '%' || lower($8) || '%'
          )
      `,
      [
        query.teacherId ?? null,
        lessonTeacherIds,
        !query.branchId && !query.unitType,
        from,
        to,
        query.status ?? null,
        query.discipline ?? null,
        query.category ?? null,
      ],
    );
    const teacherIds = namesResult.rows.map((row) => row.id);
    if (!teacherIds.length) {
      return {
        from,
        to,
        movementsScope: query.branchId
          ? "teacher_period_all_branches"
          : "teacher_period",
        items: [],
        totals: {
          completedLessons: 0,
          payableLessons: 0,
          noAccrualLessons: 0,
          hoursTotal: 0,
          accruedTotal: 0,
          bonusTotal: 0,
          deductionTotal: 0,
          paidTotal: 0,
          periodBalance: 0,
        },
      };
    }
    const lessonTeacherIdSet = new Set(lessonTeacherIds);
    const movementOnlyTeacherIds = teacherIds.filter(
      (teacherId) => !lessonTeacherIdSet.has(teacherId),
    );
    const movementOnlyRates = await this.loadTeacherRates(
      movementOnlyTeacherIds,
    );
    for (const [teacherId, entries] of movementOnlyRates) {
      rates.set(teacherId, entries);
    }
    const teacherNames = new Map(
      namesResult.rows.map((row) => [row.id, row.name || "Без имени"]),
    );
    const salaryByTeacher = new Map(
      namesResult.rows.map((row) => [
        row.id,
        row.salary === null || row.salary === undefined
          ? null
          : Number(row.salary),
      ]),
    );
    const payoutsResult = await this.database.query<{
      teacher_id: string;
      paid_total: string | number;
      bonus_total: string | number;
      deduction_total: string | number;
    }>(
      `
        select teacher_id,
          sum(case when kind = 'payout' then amount else 0 end) as paid_total,
          sum(case when kind = 'bonus' then amount else 0 end) as bonus_total,
          sum(case when kind = 'deduction' then amount else 0 end) as deduction_total
        from app.teacher_payouts
        where deleted_at is null
          and teacher_id = any($1::uuid[])
          and ($2::timestamptz is null or paid_at >= $2::timestamptz)
          and ($3::timestamptz is null or paid_at < $3::timestamptz)
        group by teacher_id
      `,
      [teacherIds, from, to],
    );
    const movementsByTeacher = new Map(
      payoutsResult.rows.map((row) => [
        row.teacher_id,
        {
          paid: Number(row.paid_total ?? 0),
          bonus: Number(row.bonus_total ?? 0),
          deduction: Number(row.deduction_total ?? 0),
        },
      ]),
    );

    interface UnitAcc {
      unitType: TeacherStatsUnitType;
      groupId: string | null;
      studentId: string | null;
      unitName: string;
      teacherRate: number | null;
      days: Map<string, number>;
      // Lesson ids behind this unit: the report's drill-down sets the
      // per-lesson rate, and only an id can address a lesson.
      lessonIds: string[];
      editableLessonIds: string[];
      settledLessons: number;
      completedLessons: number;
      payableLessons: number;
      hoursTotal: number;
      accruedTotal: number;
    }
    const teachers = new Map<
      string,
      {
        completedLessons: number;
        payableLessons: number;
        hoursTotal: number;
        accruedTotal: number;
        units: Map<string, UnitAcc>;
      }
    >();
    for (const teacherId of teacherIds) {
      teachers.set(teacherId, {
        completedLessons: 0,
        payableLessons: 0,
        hoursTotal: 0,
        accruedTotal: 0,
        units: new Map<string, UnitAcc>(),
      });
    }
    for (const lesson of lessons) {
      // teacherNames holds exactly the teachers that passed the status/
      // discipline/category filter above.
      if (!teacherNames.has(lesson.teacher_id)) continue;
      const { hours, rate, amount } = this.computeLessonAccrual(lesson, rates);
      const teacher = teachers.get(lesson.teacher_id) ?? {
        completedLessons: 0,
        payableLessons: 0,
        hoursTotal: 0,
        accruedTotal: 0,
        units: new Map<string, UnitAcc>(),
      };
      teachers.set(lesson.teacher_id, teacher);
      const unitKey = this.unitKeyFor(lesson);
      const unit = teacher.units.get(unitKey) ?? {
        unitType: this.unitTypeFor(lesson),
        groupId: lesson.group_id,
        studentId: lesson.group_id ? null : lesson.student_id,
        unitName: this.unitNameFor(lesson),
        teacherRate:
          lesson.settlement_fact_id != null
            ? rate
            : lesson.group_rate === null || lesson.group_rate === undefined
              ? null
              : Number(lesson.group_rate),
        days: new Map<string, number>(),
        lessonIds: [],
        editableLessonIds: [],
        settledLessons: 0,
        completedLessons: 0,
        payableLessons: 0,
        hoursTotal: 0,
        accruedTotal: 0,
      };
      teacher.units.set(unitKey, unit);
      unit.lessonIds.push(lesson.id);
      if (lesson.settlement_fact_id == null) {
        unit.editableLessonIds.push(lesson.id);
      } else {
        unit.settledLessons += 1;
      }
      unit.completedLessons += 1;
      teacher.completedLessons += 1;
      if (amount > 0) {
        unit.payableLessons += 1;
        teacher.payableLessons += 1;
      }
      const day = this.toDateOnly(lesson.scheduled_at);
      unit.days.set(day, (unit.days.get(day) ?? 0) + hours);
      unit.hoursTotal += hours;
      unit.accruedTotal += amount;
      teacher.hoursTotal += hours;
      teacher.accruedTotal += amount;
    }

    const totals = {
      completedLessons: 0,
      payableLessons: 0,
      hoursTotal: 0,
      accruedTotal: 0,
      bonusTotal: 0,
      deductionTotal: 0,
      paidTotal: 0,
      periodBalance: 0,
    };
    const items = [...teachers.entries()].map(([teacherId, teacher]) => {
      const movements = movementsByTeacher.get(teacherId) ?? {
        paid: 0,
        bonus: 0,
        deduction: 0,
      };
      const periodBalance =
        teacher.accruedTotal +
        movements.bonus -
        movements.deduction -
        movements.paid;
      totals.completedLessons += teacher.completedLessons;
      totals.payableLessons += teacher.payableLessons;
      totals.hoursTotal += teacher.hoursTotal;
      totals.accruedTotal += teacher.accruedTotal;
      totals.bonusTotal += movements.bonus;
      totals.deductionTotal += movements.deduction;
      totals.paidTotal += movements.paid;
      totals.periodBalance += periodBalance;
      // Актуальная ставка педагога — для колонки «ставка», когда у единицы
      // нет переопределения группы.
      const today = this.toDateOnly(new Date());
      let currentRate = 0;
      for (const entry of rates.get(teacherId) ?? []) {
        if (entry.effectiveFrom <= today) currentRate = entry.rate;
        else break;
      }
      return {
        teacherId,
        teacherName: teacherNames.get(teacherId) ?? "Без имени",
        salary: salaryByTeacher.get(teacherId) ?? null,
        currentRate,
        completedLessons: teacher.completedLessons,
        payableLessons: teacher.payableLessons,
        noAccrualLessons: teacher.completedLessons - teacher.payableLessons,
        hoursTotal: this.round2(teacher.hoursTotal),
        accruedTotal: this.round2(teacher.accruedTotal),
        bonusTotal: this.round2(movements.bonus),
        deductionTotal: this.round2(movements.deduction),
        paidTotal: this.round2(movements.paid),
        periodBalance: this.round2(periodBalance),
        units: [...teacher.units.values()].map((unit) => ({
          unitType: unit.unitType,
          groupId: unit.groupId,
          studentId: unit.studentId,
          unitName: unit.unitName,
          rate: unit.teacherRate ?? currentRate,
          days: [...unit.days.entries()]
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([date, hours]) => ({ date, hours: this.round2(hours) })),
          lessonIds: unit.lessonIds,
          editableLessonIds: unit.editableLessonIds,
          settledLessons: unit.settledLessons,
          compensationLocked: unit.settledLessons > 0,
          completedLessons: unit.completedLessons,
          payableLessons: unit.payableLessons,
          noAccrualLessons: unit.completedLessons - unit.payableLessons,
          hoursTotal: this.round2(unit.hoursTotal),
          accruedTotal: this.round2(unit.accruedTotal),
        })),
      };
    });
    items.sort((a, b) => a.teacherName.localeCompare(b.teacherName, "ru"));
    return {
      from,
      to,
      movementsScope: query.branchId
        ? "teacher_period_all_branches"
        : "teacher_period",
      items,
      totals: {
        hoursTotal: this.round2(totals.hoursTotal),
        completedLessons: totals.completedLessons,
        payableLessons: totals.payableLessons,
        noAccrualLessons: totals.completedLessons - totals.payableLessons,
        accruedTotal: this.round2(totals.accruedTotal),
        bonusTotal: this.round2(totals.bonusTotal),
        deductionTotal: this.round2(totals.deductionTotal),
        paidTotal: this.round2(totals.paidTotal),
        periodBalance: this.round2(totals.periodBalance),
      },
    };
  }

  /**
   * The same report as CSV, one row per unit — that is the shape the month-end
   * process needs (open it, sum it, hand it over), and it is what «Экспорт»
   * does in HolliHop.
   */
  async exportTeacherStatsReport(
    actor: ActorContext,
    query: TeacherStatsQuery,
  ): Promise<string> {
    const report = await this.getTeacherStatsReport(actor, query);
    const unitTypeLabel = (unitType: string) =>
      ({
        group: "Группа",
        individual: "Индивидуально",
        group_trial: "Групповой пробный",
        individual_trial: "Индивидуальный пробный",
      })[unitType] ?? "Индивидуально";
    const excelText = (value: string) =>
      /^[=+\-@]/.test(value) ? `'${value}` : value;
    const rows: string[][] = [
      [
        "Преподаватель",
        "Учебная единица",
        "Тип",
        "Дни",
        "Занятий",
        "Оплачиваемых занятий",
        "Часы",
        "Ставка за астр. час",
        "Начислено",
        "Доплаты",
        "Вычеты",
        "Оплачено",
        "Сальдо периода",
      ],
    ];
    for (const item of report.items) {
      for (const unit of item.units) {
        rows.push([
          excelText(item.teacherName),
          excelText(unit.unitName),
          excelText(unitTypeLabel(unit.unitType)),
          unit.days
            .map((day) => `${day.date} (${day.hours} астр.ч.)`)
            .join(" "),
          String(unit.completedLessons),
          String(unit.payableLessons),
          String(unit.hoursTotal),
          // 0 means «входит в оклад» — spell it out, a bare 0 reads as a bug.
          unit.rate === 0 ? "Входит в оклад" : String(unit.rate),
          String(unit.accruedTotal),
          "",
          "",
          "",
          "",
        ]);
      }
      rows.push([
        excelText(item.teacherName),
        "ИТОГО по преподавателю",
        "",
        "",
        String(item.completedLessons),
        String(item.payableLessons),
        String(item.hoursTotal),
        "",
        String(item.accruedTotal),
        String(item.bonusTotal),
        String(item.deductionTotal),
        String(item.paidTotal),
        String(item.periodBalance),
      ]);
    }
    rows.push([
      "ИТОГО",
      "",
      "",
      "",
      String(report.totals.completedLessons),
      String(report.totals.payableLessons),
      String(report.totals.hoursTotal),
      "",
      String(report.totals.accruedTotal),
      String(report.totals.bonusTotal),
      String(report.totals.deductionTotal),
      String(report.totals.paidTotal),
      String(report.totals.periodBalance),
    ]);

    const escape = (value: string) =>
      /[";\n]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value;
    // ';' separator + BOM: Excel with RU locale splits on ';', and without the
    // BOM it renders UTF-8 Cyrillic as mojibake.
    return "﻿" + rows.map((row) => row.map(escape).join(";")).join("\r\n");
  }
}
