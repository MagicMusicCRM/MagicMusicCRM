import { Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CreateTeacherPayoutDto } from "./dto/create-teacher-payout.dto";
import { SetTeacherRateDto } from "./dto/set-teacher-rate.dto";
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
  | "group"
  | "individual"
  | "group_trial"
  | "individual_trial";

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
          lp.attendance_kind, lp.charge_share
        from app.lessons l
        left join app.groups g on g.id = l.group_id and g.deleted_at is null
        left join app.students s on s.id = l.student_id and s.deleted_at is null
        left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
        -- Пробное занятие висит на лиде: без него все пробные разных людей
        -- сходились в одну безымянную строку отчёта.
        left join app.leads ld on ld.id = l.lead_id and ld.deleted_at is null
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
      // `trial` — любое пробное, групповое или нет. Оставлен как есть: это
      // разрез, которым уже пользуются, и сузить его молча значило бы менять
      // цифры под теми, кто на него смотрит.
      if (query.unitType === "trial") return lesson.is_trial;
      return this.unitTypeFor(lesson) === query.unitType;
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
    // Doubles as the teacher-attribute filter: a teacher missing from this
    // result is dropped from the report below, so status/discipline/category
    // need no second pass over the lessons.
    const namesResult = await this.database.query<{ id: string; name: string }>(
      `
        select t.id,
          trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')) as name
        from app.teachers t
        left join app.profiles p on p.id = t.profile_id and p.deleted_at is null
        where t.id = any($1::uuid[])
          and ($2::text is null or t.status = $2)
          and (
            $3::text is null
            or exists (
              select 1
              from app.teacher_disciplines td
              join app.disciplines d
                on d.id = td.discipline_id and d.deleted_at is null
              where td.teacher_id = t.id and lower(d.name) = lower($3)
            )
            -- Legacy rows carry the discipline as free text instead of the m2m.
            or lower(coalesce(t.specialization, '')) like '%' || lower($3) || '%'
          )
          and (
            $4::text is null
            or lower(
              coalesce(t.custom_data->>'categories', t.custom_data->>'category', '')
            ) like '%' || lower($4) || '%'
          )
      `,
      [
        teacherIds,
        query.status ?? null,
        query.discipline ?? null,
        query.category ?? null,
      ],
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
      unitType: TeacherStatsUnitType;
      groupId: string | null;
      studentId: string | null;
      unitName: string;
      teacherRate: number | null;
      days: Map<string, number>;
      // Lesson ids behind this unit: the report's drill-down sets the
      // per-lesson rate, and only an id can address a lesson.
      lessonIds: string[];
      hoursTotal: number;
      accruedTotal: number;
    }
    const teachers = new Map<
      string,
      { hoursTotal: number; accruedTotal: number; units: Map<string, UnitAcc> }
    >();
    for (const lesson of lessons) {
      // teacherNames holds exactly the teachers that passed the status/
      // discipline/category filter above.
      if (!teacherNames.has(lesson.teacher_id)) continue;
      const { hours, amount } = this.computeLessonAccrual(lesson, rates);
      const teacher = teachers.get(lesson.teacher_id) ?? {
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
          lesson.group_rate === null || lesson.group_rate === undefined
            ? null
            : Number(lesson.group_rate),
        days: new Map<string, number>(),
        lessonIds: [],
        hoursTotal: 0,
        accruedTotal: 0,
      };
      teacher.units.set(unitKey, unit);
      unit.lessonIds.push(lesson.id);
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
          unitType: unit.unitType,
          groupId: unit.groupId,
          studentId: unit.studentId,
          unitName: unit.unitName,
          rate: unit.teacherRate ?? currentRate,
          days: [...unit.days.entries()]
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([date, hours]) => ({ date, hours: this.round2(hours) })),
          lessonIds: unit.lessonIds,
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
    const rows: string[][] = [
      [
        "Преподаватель",
        "Учебная единица",
        "Тип",
        "Дни",
        "Часы",
        "Ставка за ак. час",
        "Начислено",
        "Оплачено",
      ],
    ];
    for (const item of report.items) {
      for (const unit of item.units) {
        rows.push([
          item.teacherName,
          unit.unitName,
          unitTypeLabel(unit.unitType),
          unit.days.map((day) => day.date).join(" "),
          String(unit.hoursTotal),
          // 0 means «входит в оклад» — spell it out, a bare 0 reads as a bug.
          unit.rate === 0 ? "Входит в оклад" : String(unit.rate),
          String(unit.accruedTotal),
          "",
        ]);
      }
      rows.push([
        item.teacherName,
        "ИТОГО по преподавателю",
        "",
        "",
        String(item.hoursTotal),
        "",
        String(item.accruedTotal),
        String(item.paidTotal),
      ]);
    }
    rows.push([
      "ИТОГО",
      "",
      "",
      "",
      String(report.totals.hoursTotal),
      "",
      String(report.totals.accruedTotal),
      String(report.totals.paidTotal),
    ]);

    const escape = (value: string) =>
      /[";\n]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value;
    // ';' separator + BOM: Excel with RU locale splits on ';', and without the
    // BOM it renders UTF-8 Cyrillic as mojibake.
    return (
      "﻿" + rows.map((row) => row.map(escape).join(";")).join("\r\n")
    );
  }
}
