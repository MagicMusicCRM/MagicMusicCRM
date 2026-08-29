import { Injectable } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import {
  OoxmlCell,
  OoxmlWorkbookBuilder,
} from "../../common/ooxml-workbook.builder";
import { TeacherStatsQuery } from "../dto/teacher-stats.query";
import { TeacherStatsReportService } from "./teacher-stats-report.service";

@Injectable()
export class TeacherStatsXlsxService {
  constructor(
    private readonly report: TeacherStatsReportService,
    private readonly workbook: OoxmlWorkbookBuilder,
  ) {}

  async exportTeacherStatsReport(
    actor: ActorContext,
    query: TeacherStatsQuery,
  ): Promise<Buffer> {
    const report = await this.report.getTeacherStatsReport(actor, query);
    const rows: OoxmlCell[][] = [];
    for (const item of report.items) {
      for (const unit of item.units) rows.push(this.unitRow(item, unit));
      rows.push([
        this.excelText(item.teacherName),
        "ИТОГО по преподавателю",
        "",
        "",
        item.completedLessons,
        item.payableLessons,
        item.hoursTotal,
        "",
        item.accruedTotal,
      ]);
    }
    rows.push([
      "ИТОГО",
      "",
      "",
      "",
      report.totals.completedLessons,
      report.totals.payableLessons,
      report.totals.hoursTotal,
      "",
      report.totals.accruedTotal,
    ]);
    return this.workbook.build({
      sheetName: "Начисления преподавателей",
      columns: [
        { key: "teacher", header: "Преподаватель", type: "string" },
        { key: "unit", header: "Учебная единица", type: "string" },
        { key: "type", header: "Тип", type: "string" },
        { key: "days", header: "Дни", type: "string", width: 32 },
        { key: "lessons", header: "Занятий", type: "number" },
        { key: "payable", header: "Оплачиваемых занятий", type: "number" },
        { key: "hours", header: "Часы", type: "number" },
        { key: "rate", header: "Ставка за астр. час", type: "string" },
        { key: "accrued", header: "Начислено", type: "money" },
      ],
      rows,
    });
  }

  private unitRow(
    item: { teacherName: string },
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
  ): OoxmlCell[] {
    return [
      this.excelText(item.teacherName),
      this.excelText(unit.unitName),
      this.excelText(this.unitTypeLabel(unit.unitType)),
      unit.days.map((day) => `${day.date} (${day.hours} астр.ч.)`).join(" "),
      unit.completedLessons,
      unit.payableLessons,
      unit.hoursTotal,
      unit.rate === 0 ? "Входит в оклад" : String(unit.rate),
      unit.accruedTotal,
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
}
