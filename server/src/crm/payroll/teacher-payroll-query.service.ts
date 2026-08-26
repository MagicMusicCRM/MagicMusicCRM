import { Injectable, NotFoundException } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { CrmPolicy } from "../crm.policy";
import { PayrollAccrualCalculator } from "./payroll-accrual-calculator";
import { PayrollReadRepository } from "./payroll-read.repository";
import { TeacherPayoutRow, TeacherRateEntry } from "./payroll.types";

@Injectable()
export class TeacherPayrollQueryService {
  constructor(
    private readonly repository: PayrollReadRepository,
    private readonly policy: CrmPolicy,
    private readonly calculator: PayrollAccrualCalculator,
  ) {}

  async getTeacherPayroll(actor: ActorContext, teacherId: string) {
    this.policy.assertCanReadPayroll(actor);
    const header = await this.repository.findTeacherPayrollHeader(teacherId);
    if (!header) throw new NotFoundException("Преподаватель не найден.");

    const lessons = await this.repository.loadPayrollLessons({ teacherId });
    const rates = await this.repository.loadTeacherRates([teacherId]);
    const lessonTotals = lessons.reduce(
      (totals, lesson) => {
        const accrual = this.calculator.computeLessonAccrual(lesson, rates);
        totals.hours += accrual.hours;
        totals.accrued += accrual.amount;
        if (accrual.amount > 0) totals.payable += 1;
        return totals;
      },
      { hours: 0, accrued: 0, payable: 0 },
    );
    const payouts = await this.repository.listTeacherPayouts(teacherId);
    const movementTotals = this.sumMovements(payouts);
    const rateHistory = rates.get(teacherId) ?? [];
    const currentRate = this.currentRate(rateHistory);

    return {
      teacherId,
      version: Number(header.version),
      hoursTotal: this.calculator.round2(lessonTotals.hours),
      completedLessons: lessons.length,
      payableLessons: lessonTotals.payable,
      noAccrualLessons: lessons.length - lessonTotals.payable,
      accruedTotal: this.calculator.round2(lessonTotals.accrued),
      bonusTotal: this.calculator.round2(movementTotals.bonus),
      deductionTotal: this.calculator.round2(movementTotals.deduction),
      paidTotal: this.calculator.round2(movementTotals.paid),
      debt: this.calculator.round2(
        lessonTotals.accrued +
          movementTotals.bonus -
          movementTotals.deduction -
          movementTotals.paid,
      ),
      currentRate,
      rateHistory,
      payouts: payouts.map((row) => this.toPayout(row)),
    };
  }

  private sumMovements(rows: TeacherPayoutRow[]) {
    const totals = { paid: 0, bonus: 0, deduction: 0 };
    for (const row of rows) {
      const amount = Number(row.amount);
      if (row.kind === "payout") totals.paid += amount;
      else if (row.kind === "bonus") totals.bonus += amount;
      else totals.deduction += amount;
    }
    return totals;
  }

  private currentRate(history: TeacherRateEntry[]): number | null {
    const today = this.calculator.toDateOnly(new Date());
    let current: number | null = null;
    for (const entry of history) {
      if (entry.effectiveFrom > today) break;
      current = entry.rate;
    }
    return current;
  }

  private toPayout(row: TeacherPayoutRow) {
    return {
      id: row.id,
      kind: row.kind,
      amount: Number(row.amount),
      comment: row.comment,
      paidAt: row.paid_at,
      authorName:
        [row.author_first_name, row.author_last_name].filter(Boolean).join(" ") ||
        null,
    };
  }
}
