import { Injectable } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { TeacherStatsQuery } from "../dto/teacher-stats.query";
import { TeacherStatsReportService } from "./teacher-stats-report.service";

@Injectable()
export class TeacherStatsCsvService {
  constructor(private readonly report: TeacherStatsReportService) {}

  async exportTeacherStatsReport(
    actor: ActorContext,
    query: TeacherStatsQuery,
  ): Promise<string> {
    const report = await this.report.getTeacherStatsReport(actor, query);
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
      for (const unit of item.units) rows.push(this.unitRow(item, unit));
      rows.push([
        this.excelText(item.teacherName),
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
    return "﻿" + rows.map((row) => row.map(this.escape).join(";")).join("\r\n");
  }

  private unitRow(
    item: {
      teacherName: string;
    },
    unit: {
      unitName: string;
      unitType: string;
      days: { date: string; hours: number }[];
      completedLessons: number;
      payableLessons: number;
      hoursTotal: number;
      rate: number;
      accruedTotal: number;
    },
  ): string[] {
    return [
      this.excelText(item.teacherName),
      this.excelText(unit.unitName),
      this.excelText(this.unitTypeLabel(unit.unitType)),
      unit.days.map((day) => `${day.date} (${day.hours} астр.ч.)`).join(" "),
      String(unit.completedLessons),
      String(unit.payableLessons),
      String(unit.hoursTotal),
      unit.rate === 0 ? "Входит в оклад" : String(unit.rate),
      String(unit.accruedTotal),
      "",
      "",
      "",
      "",
    ];
  }

  private unitTypeLabel(unitType: string): string {
    return (
      {
        group: "Группа",
        individual: "Индивидуально",
        group_trial: "Групповой пробный",
        individual_trial: "Индивидуальный пробный",
      }[unitType] ?? "Индивидуально"
    );
  }

  private excelText(value: string): string {
    return /^[=+\-@]/.test(value) ? `'${value}` : value;
  }

  private escape(value: string): string {
    return /[";\n]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value;
  }
}
