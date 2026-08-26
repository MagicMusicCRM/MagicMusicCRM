import { Injectable } from "@nestjs/common";
import {
  PayrollLessonAccrual,
  PayrollLessonRow,
  TeacherRateEntry,
  TeacherStatsUnitType,
} from "./payroll.types";

@Injectable()
export class PayrollAccrualCalculator {
  toDateOnly(value: Date | string): string {
    if (value instanceof Date) {
      const year = value.getFullYear();
      const month = String(value.getMonth() + 1).padStart(2, "0");
      const day = String(value.getDate()).padStart(2, "0");
      return `${year}-${month}-${day}`;
    }
    return String(value).slice(0, 10);
  }

  round2(value: number): number {
    return Math.round(value * 100) / 100;
  }

  computeLessonAccrual(
    lesson: PayrollLessonRow,
    rates: Map<string, TeacherRateEntry[]>,
  ): PayrollLessonAccrual {
    const hours = Number(lesson.duration_minutes ?? 0) / 60;
    const settled = this.settledAccrual(lesson, hours);
    if (settled) return settled;
    const rate = this.effectiveRate(lesson, rates);
    const coefficient = this.attendanceCoefficient(lesson);
    return {
      hours,
      rate,
      coefficient,
      amount: this.roundedAmount(hours, rate, coefficient),
    };
  }

  unitTypeFor(lesson: PayrollLessonRow): TeacherStatsUnitType {
    if (lesson.group_id) return lesson.is_trial ? "group_trial" : "group";
    return lesson.is_trial ? "individual_trial" : "individual";
  }

  unitKeyFor(lesson: PayrollLessonRow): string {
    if (lesson.group_id) {
      return lesson.is_trial ? `gt:${lesson.group_id}` : `g:${lesson.group_id}`;
    }
    if (!lesson.is_trial) return `s:${lesson.student_id ?? "unknown"}`;
    return `t:${lesson.lead_id ?? lesson.student_id ?? "unknown"}`;
  }

  unitNameFor(lesson: PayrollLessonRow): string {
    if (lesson.group_id) return lesson.group_name ?? "Группа";
    const person =
      lesson.student_name?.trim() || lesson.lead_name?.trim() || "";
    if (person) return person;
    return lesson.is_trial ? "Пробное занятие" : "Без имени";
  }

  private settledAccrual(
    lesson: PayrollLessonRow,
    hours: number,
  ): PayrollLessonAccrual | null {
    if (
      lesson.settlement_fact_id == null ||
      lesson.settled_amount_minor == null
    ) {
      return null;
    }
    const amount = Number(lesson.settled_amount_minor) / 100;
    return {
      hours,
      rate: hours > 0 ? this.round2(amount / hours) : 0,
      coefficient: 1,
      amount: this.round2(amount),
    };
  }

  private effectiveRate(
    lesson: PayrollLessonRow,
    rates: Map<string, TeacherRateEntry[]>,
  ): number {
    if (lesson.teacher_rate !== null && lesson.teacher_rate !== undefined) {
      return Number(lesson.teacher_rate);
    }
    if (lesson.group_rate !== null && lesson.group_rate !== undefined) {
      return Number(lesson.group_rate);
    }
    return this.historicalRate(lesson, rates);
  }

  private historicalRate(
    lesson: PayrollLessonRow,
    rates: Map<string, TeacherRateEntry[]>,
  ): number {
    const lessonDate = this.toDateOnly(lesson.scheduled_at);
    let effective = 0;
    for (const entry of rates.get(lesson.teacher_id) ?? []) {
      if (entry.effectiveFrom > lessonDate) break;
      effective = entry.rate;
    }
    return effective;
  }

  private attendanceCoefficient(lesson: PayrollLessonRow): number {
    if (!lesson.student_id) return 1;
    if (lesson.attendance_kind === "unpaid_miss") return 0;
    if (lesson.attendance_kind === "partially_paid") {
      return Number(lesson.charge_share ?? 1);
    }
    return 1;
  }

  private roundedAmount(
    hours: number,
    rate: number,
    coefficient: number,
  ): number {
    return Math.round(hours * rate * coefficient * 100) / 100;
  }
}
