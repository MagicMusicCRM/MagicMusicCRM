import { BadRequestException, Injectable } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { CrmPolicy } from "../crm.policy";
import { TeacherStatsQuery } from "../dto/teacher-stats.query";
import { PayrollAccrualCalculator } from "./payroll-accrual-calculator";
import { PayrollReadRepository } from "./payroll-read.repository";
import {
  PayrollLessonRow,
  TeacherMovementTotals,
  TeacherRateEntry,
  TeacherReportRow,
  TeacherStatsUnitType,
} from "./payroll.types";

interface ReportPeriod {
  from: string;
  to: string;
}

interface UnitAccumulator {
  unitType: TeacherStatsUnitType;
  groupId: string | null;
  studentId: string | null;
  unitName: string;
  teacherRate: number | null;
  days: Map<string, number>;
  lessonIds: string[];
  editableLessonIds: string[];
  settledLessons: number;
  completedLessons: number;
  payableLessons: number;
  hoursTotal: number;
  accruedTotal: number;
}

interface TeacherAccumulator {
  completedLessons: number;
  payableLessons: number;
  hoursTotal: number;
  accruedTotal: number;
  units: Map<string, UnitAccumulator>;
}

interface ReportTotals {
  completedLessons: number;
  payableLessons: number;
  hoursTotal: number;
  accruedTotal: number;
  bonusTotal: number;
  deductionTotal: number;
  paidTotal: number;
  periodBalance: number;
}

@Injectable()
export class TeacherStatsReportService {
  constructor(
    private readonly repository: PayrollReadRepository,
    private readonly policy: CrmPolicy,
    private readonly calculator: PayrollAccrualCalculator,
  ) {}

  async getTeacherStatsReport(actor: ActorContext, query: TeacherStatsQuery) {
    this.policy.assertCanReadPayroll(actor);
    const period = this.resolvePeriod(query);
    const loadedLessons = await this.repository.loadPayrollLessons({
      teacherId: query.teacherId,
      branchId: query.branchId,
      from: period.from,
      to: period.to,
    });
    const lessons = this.filterLessons(loadedLessons, query);
    const lessonTeacherIds = [...new Set(lessons.map((row) => row.teacher_id))];
    const rates = await this.repository.loadTeacherRates(lessonTeacherIds);
    const rows = await this.selectTeachers(query, period, lessonTeacherIds);
    const teacherIds = rows.map((row) => row.id);
    if (!teacherIds.length) return this.emptyReport(period, query);

    await this.mergeMovementOnlyRates(rates, teacherIds, lessonTeacherIds);
    const movements = await this.repository.loadPeriodMovements(
      teacherIds,
      period.from,
      period.to,
    );
    const teachers = this.initializeTeachers(teacherIds);
    const names = new Map(
      rows.map((row) => [row.id, row.name || "Без имени"]),
    );
    const salaries = new Map(
      rows.map((row) => [row.id, this.numericSalary(row)]),
    );
    this.accumulateLessons(lessons, teachers, names, rates);
    const totals = this.emptyTotals();
    const items = this.projectTeachers(
      teachers,
      names,
      salaries,
      rates,
      movements,
      totals,
    );
    items.sort((a, b) => a.teacherName.localeCompare(b.teacherName, "ru"));
    return {
      ...period,
      movementsScope: this.movementsScope(query),
      items,
      totals: this.projectTotals(totals),
    };
  }

  private resolvePeriod(query: TeacherStatsQuery): ReportPeriod {
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
    return { from, to };
  }

  private filterLessons(
    lessons: PayrollLessonRow[],
    query: TeacherStatsQuery,
  ): PayrollLessonRow[] {
    if (!query.unitType) return lessons;
    if (query.unitType === "trial") {
      return lessons.filter((lesson) => lesson.is_trial);
    }
    return lessons.filter(
      (lesson) => this.calculator.unitTypeFor(lesson) === query.unitType,
    );
  }

  private selectTeachers(
    query: TeacherStatsQuery,
    period: ReportPeriod,
    lessonTeacherIds: string[],
  ): Promise<TeacherReportRow[]> {
    return this.repository.listReportTeachers({
      teacherId: query.teacherId ?? null,
      lessonTeacherIds,
      includeMovementOnly: !query.branchId && !query.unitType,
      from: period.from,
      to: period.to,
      status: query.status ?? null,
      discipline: query.discipline ?? null,
      category: query.category ?? null,
    });
  }

  private async mergeMovementOnlyRates(
    rates: Map<string, TeacherRateEntry[]>,
    teacherIds: string[],
    lessonTeacherIds: string[],
  ): Promise<void> {
    const lessonTeacherSet = new Set(lessonTeacherIds);
    const movementOnlyIds = teacherIds.filter((id) => !lessonTeacherSet.has(id));
    const movementRates = await this.repository.loadTeacherRates(movementOnlyIds);
    for (const [teacherId, entries] of movementRates) {
      rates.set(teacherId, entries);
    }
  }

  private initializeTeachers(ids: string[]): Map<string, TeacherAccumulator> {
    return new Map(ids.map((id) => [id, this.emptyTeacher()]));
  }

  private emptyTeacher(): TeacherAccumulator {
    return {
      completedLessons: 0,
      payableLessons: 0,
      hoursTotal: 0,
      accruedTotal: 0,
      units: new Map(),
    };
  }

  private accumulateLessons(
    lessons: PayrollLessonRow[],
    teachers: Map<string, TeacherAccumulator>,
    names: Map<string, string>,
    rates: Map<string, TeacherRateEntry[]>,
  ): void {
    for (const lesson of lessons) {
      if (!names.has(lesson.teacher_id)) continue;
      this.accumulateLesson(lesson, teachers, rates);
    }
  }

  private accumulateLesson(
    lesson: PayrollLessonRow,
    teachers: Map<string, TeacherAccumulator>,
    rates: Map<string, TeacherRateEntry[]>,
  ): void {
    const accrual = this.calculator.computeLessonAccrual(lesson, rates);
    const teacher = teachers.get(lesson.teacher_id) ?? this.emptyTeacher();
    teachers.set(lesson.teacher_id, teacher);
    const key = this.calculator.unitKeyFor(lesson);
    const unit = teacher.units.get(key) ?? this.newUnit(lesson, accrual.rate);
    teacher.units.set(key, unit);
    unit.lessonIds.push(lesson.id);
    if (lesson.settlement_fact_id == null) unit.editableLessonIds.push(lesson.id);
    else unit.settledLessons += 1;
    unit.completedLessons += 1;
    teacher.completedLessons += 1;
    if (accrual.amount > 0) {
      unit.payableLessons += 1;
      teacher.payableLessons += 1;
    }
    const day = this.calculator.toDateOnly(lesson.scheduled_at);
    unit.days.set(day, (unit.days.get(day) ?? 0) + accrual.hours);
    unit.hoursTotal += accrual.hours;
    unit.accruedTotal += accrual.amount;
    teacher.hoursTotal += accrual.hours;
    teacher.accruedTotal += accrual.amount;
  }

  private newUnit(lesson: PayrollLessonRow, rate: number): UnitAccumulator {
    return {
      unitType: this.calculator.unitTypeFor(lesson),
      groupId: lesson.group_id,
      studentId: lesson.group_id ? null : lesson.student_id,
      unitName: this.calculator.unitNameFor(lesson),
      teacherRate:
        lesson.settlement_fact_id != null
          ? rate
          : lesson.group_rate == null
            ? null
            : Number(lesson.group_rate),
      days: new Map(),
      lessonIds: [],
      editableLessonIds: [],
      settledLessons: 0,
      completedLessons: 0,
      payableLessons: 0,
      hoursTotal: 0,
      accruedTotal: 0,
    };
  }

  private projectTeachers(
    teachers: Map<string, TeacherAccumulator>,
    names: Map<string, string>,
    salaries: Map<string, number | null>,
    rates: Map<string, TeacherRateEntry[]>,
    movements: Map<string, TeacherMovementTotals>,
    totals: ReportTotals,
  ) {
    return [...teachers.entries()].map(([teacherId, teacher]) => {
      const movement = movements.get(teacherId) ?? {
        paid: 0,
        bonus: 0,
        deduction: 0,
      };
      const periodBalance =
        teacher.accruedTotal + movement.bonus - movement.deduction - movement.paid;
      this.addTeacherTotals(totals, teacher, movement, periodBalance);
      const currentRate = this.currentRate(rates.get(teacherId) ?? []);
      return {
        teacherId,
        teacherName: names.get(teacherId) ?? "Без имени",
        salary: salaries.get(teacherId) ?? null,
        currentRate,
        completedLessons: teacher.completedLessons,
        payableLessons: teacher.payableLessons,
        noAccrualLessons: teacher.completedLessons - teacher.payableLessons,
        hoursTotal: this.calculator.round2(teacher.hoursTotal),
        accruedTotal: this.calculator.round2(teacher.accruedTotal),
        bonusTotal: this.calculator.round2(movement.bonus),
        deductionTotal: this.calculator.round2(movement.deduction),
        paidTotal: this.calculator.round2(movement.paid),
        periodBalance: this.calculator.round2(periodBalance),
        units: [...teacher.units.values()].map((unit) =>
          this.projectUnit(unit, currentRate),
        ),
      };
    });
  }

  private projectUnit(unit: UnitAccumulator, currentRate: number) {
    return {
      unitType: unit.unitType,
      groupId: unit.groupId,
      studentId: unit.studentId,
      unitName: unit.unitName,
      rate: unit.teacherRate ?? currentRate,
      days: [...unit.days.entries()]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([date, hours]) => ({
          date,
          hours: this.calculator.round2(hours),
        })),
      lessonIds: unit.lessonIds,
      editableLessonIds: unit.editableLessonIds,
      settledLessons: unit.settledLessons,
      compensationLocked: unit.settledLessons > 0,
      completedLessons: unit.completedLessons,
      payableLessons: unit.payableLessons,
      noAccrualLessons: unit.completedLessons - unit.payableLessons,
      hoursTotal: this.calculator.round2(unit.hoursTotal),
      accruedTotal: this.calculator.round2(unit.accruedTotal),
    };
  }

  private currentRate(entries: TeacherRateEntry[]): number {
    const today = this.calculator.toDateOnly(new Date());
    let current = 0;
    for (const entry of entries) {
      if (entry.effectiveFrom > today) break;
      current = entry.rate;
    }
    return current;
  }

  private addTeacherTotals(
    totals: ReportTotals,
    teacher: TeacherAccumulator,
    movement: TeacherMovementTotals,
    periodBalance: number,
  ): void {
    totals.completedLessons += teacher.completedLessons;
    totals.payableLessons += teacher.payableLessons;
    totals.hoursTotal += teacher.hoursTotal;
    totals.accruedTotal += teacher.accruedTotal;
    totals.bonusTotal += movement.bonus;
    totals.deductionTotal += movement.deduction;
    totals.paidTotal += movement.paid;
    totals.periodBalance += periodBalance;
  }

  private projectTotals(totals: ReportTotals) {
    return {
      hoursTotal: this.calculator.round2(totals.hoursTotal),
      completedLessons: totals.completedLessons,
      payableLessons: totals.payableLessons,
      noAccrualLessons: totals.completedLessons - totals.payableLessons,
      accruedTotal: this.calculator.round2(totals.accruedTotal),
      bonusTotal: this.calculator.round2(totals.bonusTotal),
      deductionTotal: this.calculator.round2(totals.deductionTotal),
      paidTotal: this.calculator.round2(totals.paidTotal),
      periodBalance: this.calculator.round2(totals.periodBalance),
    };
  }

  private emptyTotals(): ReportTotals {
    return {
      completedLessons: 0,
      payableLessons: 0,
      hoursTotal: 0,
      accruedTotal: 0,
      bonusTotal: 0,
      deductionTotal: 0,
      paidTotal: 0,
      periodBalance: 0,
    };
  }

  private emptyReport(period: ReportPeriod, query: TeacherStatsQuery) {
    return {
      ...period,
      movementsScope: this.movementsScope(query),
      items: [],
      totals: {
        ...this.projectTotals(this.emptyTotals()),
      },
    };
  }

  private movementsScope(query: TeacherStatsQuery): string {
    return query.branchId ? "teacher_period_all_branches" : "teacher_period";
  }

  private numericSalary(row: TeacherReportRow): number | null {
    return row.salary === null || row.salary === undefined
      ? null
      : Number(row.salary);
  }
}
