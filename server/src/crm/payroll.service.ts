import { Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CreateTeacherPayoutDto } from "./dto/create-teacher-payout.dto";
import { SetTeacherRateDto } from "./dto/set-teacher-rate.dto";
import { TeacherStatsQuery } from "./dto/teacher-stats.query";
import { CrmPolicy } from "./crm.policy";
import { trimOptional } from "./crm-util";

/** Проведённое занятие для расчёта начисления (проекция, не материализуется). */
interface PayrollLessonRow {
  id: string;
  teacher_id: string;
  student_id: string | null;
  group_id: string | null;
  group_name: string | null;
  student_name: string | null;
  scheduled_at: Date | string;
  duration_minutes: number | string;
  is_trial: boolean;
  group_rate: string | number | null;
  teacher_rate: string | number | null;
  attendance_kind: string | null;
  charge_share: string | number | null;
}

interface TeacherRateRow {
  id?: string;
  teacher_id: string;
  rate: string | number;
  effective_from: Date | string;
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
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
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
    ratesByTeacher: Map<string, Array<{ rate: number; effectiveFrom: string }>>,
  ): { hours: number; rate: number; coefficient: number; amount: number } {
    const hours = Number(lesson.duration_minutes ?? 0) / 60;
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
    return { hours, rate, coefficient, amount: hours * rate * coefficient };
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
        select l.id, l.teacher_id, l.student_id, l.group_id,
          l.scheduled_at, l.duration_minutes, l.is_trial,
          l.teacher_rate, g.teacher_rate as group_rate, g.name as group_name,
          trim(coalesce(sp.first_name, '') || ' ' || coalesce(sp.last_name, '')) as student_name,
          lp.attendance_kind, lp.charge_share
        from app.lessons l
        left join app.groups g on g.id = l.group_id and g.deleted_at is null
        left join app.students s on s.id = l.student_id and s.deleted_at is null
        left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
        left join app.lesson_participation lp
          on lp.lesson_id = l.id and lp.student_id = l.student_id
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

  /** История ставок педагогов, отсортированная по effective_from. */
  private async loadTeacherRates(
    teacherIds: string[],
  ): Promise<Map<string, Array<{ rate: number; effectiveFrom: string }>>> {
    const map = new Map<string, Array<{ rate: number; effectiveFrom: string }>>();
    if (!teacherIds.length) return map;
    const result = await this.database.query<TeacherRateRow>(
      `
        select teacher_id, rate, effective_from
        from app.teacher_rates
        where teacher_id = any($1::uuid[])
        order by teacher_id, effective_from asc, created_at asc
      `,
      [teacherIds],
    );
    for (const row of result.rows) {
      const list = map.get(row.teacher_id) ?? [];
      list.push({
        rate: Number(row.rate),
        effectiveFrom: this.toDateOnly(row.effective_from),
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
    const lessons = await this.loadPayrollLessons({ teacherId });
    const rates = await this.loadTeacherRates([teacherId]);
    let accruedTotal = 0;
    let hoursTotal = 0;
    for (const lesson of lessons) {
      const { hours, amount } = this.computeLessonAccrual(lesson, rates);
      hoursTotal += hours;
      accruedTotal += amount;
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
      hoursTotal: this.round2(hoursTotal),
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
  ) {
    this.policy.assertCanReadPayroll(actor);
    const teacher = await this.database.query<{ id: string }>(
      `select id from app.teachers where id = $1 and deleted_at is null`,
      [teacherId],
    );
    if (!teacher.rows[0]) {
      throw new NotFoundException("Преподаватель не найден.");
    }
    const result = await this.database.query<TeacherPayoutRow>(
      `
        insert into app.teacher_payouts
          (teacher_id, amount, kind, comment, paid_at, created_by)
        values ($1, $2, $3, $4, coalesce($5::timestamptz, now()), $6)
        returning id, teacher_id, amount, kind, comment, paid_at
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
    const payout = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.teacher_payout_created",
      entityType: "teacher",
      entityId: teacherId,
      metadata: { kind: dto.kind, amount: dto.amount },
    });
    return {
      id: payout.id,
      teacherId: payout.teacher_id,
      kind: payout.kind,
      amount: Number(payout.amount),
      comment: payout.comment,
      paidAt: payout.paid_at,
    };
  }

  /** KVA-238: новая ставка педагога (история сохраняется, 0 = «входит в оклад»). */
  async setTeacherRate(
    actor: ActorContext,
    teacherId: string,
    dto: SetTeacherRateDto,
  ) {
    this.policy.assertCanReadPayroll(actor);
    const teacher = await this.database.query<{ id: string }>(
      `select id from app.teachers where id = $1 and deleted_at is null`,
      [teacherId],
    );
    if (!teacher.rows[0]) {
      throw new NotFoundException("Преподаватель не найден.");
    }
    const result = await this.database.query<TeacherRateRow>(
      `
        insert into app.teacher_rates (teacher_id, rate, effective_from, created_by)
        values ($1, $2, coalesce($3::date, current_date), $4)
        returning id, teacher_id, rate, effective_from
      `,
      [teacherId, dto.rate, dto.effectiveFrom ?? null, actor.userId],
    );
    const rate = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.teacher_rate_set",
      entityType: "teacher",
      entityId: teacherId,
      metadata: { rate: dto.rate, effectiveFrom: dto.effectiveFrom ?? null },
    });
    return {
      id: rate.id,
      teacherId: rate.teacher_id,
      rate: Number(rate.rate),
      effectiveFrom: this.toDateOnly(rate.effective_from),
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
      new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();
    const to = query.to ?? null;
    const lessons = (
      await this.loadPayrollLessons({
        teacherId: query.teacherId,
        branchId: query.branchId,
        from,
        to,
      })
    ).filter((lesson) => {
      if (!query.unitType) return true;
      if (query.unitType === "trial") return lesson.is_trial;
      if (query.unitType === "group")
        return !!lesson.group_id && !lesson.is_trial;
      return !lesson.group_id && !lesson.is_trial;
    });
    const teacherIds = [...new Set(lessons.map((l) => l.teacher_id))];
    if (!teacherIds.length) {
      return {
        from,
        to,
        items: [],
        totals: { hoursTotal: 0, accruedTotal: 0, paidTotal: 0 },
      };
    }
    const rates = await this.loadTeacherRates(teacherIds);
    const namesResult = await this.database.query<{ id: string; name: string }>(
      `
        select t.id,
          trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')) as name
        from app.teachers t
        left join app.profiles p on p.id = t.profile_id and p.deleted_at is null
        where t.id = any($1::uuid[])
      `,
      [teacherIds],
    );
    const teacherNames = new Map(
      namesResult.rows.map((row) => [row.id, row.name || "Без имени"]),
    );
    const payoutsResult = await this.database.query<{
      teacher_id: string;
      paid_total: string | number;
    }>(
      `
        select teacher_id,
          sum(case when kind = 'payout' then amount else 0 end) as paid_total
        from app.teacher_payouts
        where deleted_at is null
          and teacher_id = any($1::uuid[])
          and ($2::timestamptz is null or paid_at >= $2::timestamptz)
          and ($3::timestamptz is null or paid_at < $3::timestamptz)
        group by teacher_id
      `,
      [teacherIds, from, to],
    );
    const paidByTeacher = new Map(
      payoutsResult.rows.map((row) => [row.teacher_id, Number(row.paid_total)]),
    );

    interface UnitAcc {
      unitType: "group" | "individual" | "trial";
      groupId: string | null;
      studentId: string | null;
      unitName: string;
      teacherRate: number | null;
      days: Map<string, number>;
      hoursTotal: number;
      accruedTotal: number;
      hasRegular: boolean;
    }
    const teachers = new Map<
      string,
      { hoursTotal: number; accruedTotal: number; units: Map<string, UnitAcc> }
    >();
    for (const lesson of lessons) {
      const { hours, amount } = this.computeLessonAccrual(lesson, rates);
      const teacher = teachers.get(lesson.teacher_id) ?? {
        hoursTotal: 0,
        accruedTotal: 0,
        units: new Map<string, UnitAcc>(),
      };
      teachers.set(lesson.teacher_id, teacher);
      const unitKey = lesson.group_id
        ? `g:${lesson.group_id}`
        : `s:${lesson.student_id ?? "trial"}`;
      const unit = teacher.units.get(unitKey) ?? {
        unitType: lesson.group_id ? ("group" as const) : ("trial" as const),
        groupId: lesson.group_id,
        studentId: lesson.group_id ? null : lesson.student_id,
        unitName: lesson.group_id
          ? (lesson.group_name ?? "Группа")
          : lesson.student_name?.trim() || "Пробное занятие",
        teacherRate:
          lesson.group_rate === null || lesson.group_rate === undefined
            ? null
            : Number(lesson.group_rate),
        days: new Map<string, number>(),
        hoursTotal: 0,
        accruedTotal: 0,
        hasRegular: false,
      };
      teacher.units.set(unitKey, unit);
      if (!lesson.is_trial) unit.hasRegular = true;
      const day = this.toDateOnly(lesson.scheduled_at);
      unit.days.set(day, (unit.days.get(day) ?? 0) + hours);
      unit.hoursTotal += hours;
      unit.accruedTotal += amount;
      teacher.hoursTotal += hours;
      teacher.accruedTotal += amount;
    }

    const totals = { hoursTotal: 0, accruedTotal: 0, paidTotal: 0 };
    const items = [...teachers.entries()].map(([teacherId, teacher]) => {
      const paidTotal = paidByTeacher.get(teacherId) ?? 0;
      totals.hoursTotal += teacher.hoursTotal;
      totals.accruedTotal += teacher.accruedTotal;
      totals.paidTotal += paidTotal;
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
        hoursTotal: this.round2(teacher.hoursTotal),
        accruedTotal: this.round2(teacher.accruedTotal),
        paidTotal: this.round2(paidTotal),
        units: [...teacher.units.values()].map((unit) => ({
          unitType:
            unit.unitType === "group"
              ? "group"
              : unit.hasRegular
                ? "individual"
                : "trial",
          groupId: unit.groupId,
          studentId: unit.studentId,
          unitName: unit.unitName,
          rate: unit.teacherRate ?? currentRate,
          days: [...unit.days.entries()]
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([date, hours]) => ({ date, hours: this.round2(hours) })),
          hoursTotal: this.round2(unit.hoursTotal),
          accruedTotal: this.round2(unit.accruedTotal),
        })),
      };
    });
    items.sort((a, b) => a.teacherName.localeCompare(b.teacherName, "ru"));
    return {
      from,
      to,
      items,
      totals: {
        hoursTotal: this.round2(totals.hoursTotal),
        accruedTotal: this.round2(totals.accruedTotal),
        paidTotal: this.round2(totals.paidTotal),
      },
    };
  }
}
