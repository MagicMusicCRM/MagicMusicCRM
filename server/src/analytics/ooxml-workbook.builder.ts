import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import { PassThrough } from "stream";
import * as ExcelJS from "exceljs";

export type OoxmlColumnType =
  | "string"
  | "number"
  | "date"
  | "money"
  | "formula";

export interface OoxmlColumn {
  key: string;
  header: string;
  type: OoxmlColumnType;
  width?: number;
}

export type OoxmlCell =
  | string
  | number
  | Date
  | null
  | { formula: string; result: number };

export interface OoxmlWorkbookInput {
  sheetName: string;
  columns: readonly OoxmlColumn[];
  rows: readonly (readonly OoxmlCell[])[];
}

export const XLSX_MIME =
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
export const CSV_MIME = "text/csv; charset=utf-8";
export const SYNC_EXPORT_ROW_LIMIT = 10_000;
export const ASYNC_EXPORT_ROW_LIMIT = 100_000;

export function exportModeForRowCount(
  rowCount: number,
): "sync" | "async" {
  if (!Number.isInteger(rowCount) || rowCount < 0) {
    throw new UnprocessableEntityException({
      code: "INVALID_EXPORT_ROW_COUNT",
      message: "Export row count is invalid.",
    });
  }
  if (rowCount <= SYNC_EXPORT_ROW_LIMIT) return "sync";
  if (rowCount <= ASYNC_EXPORT_ROW_LIMIT) return "async";
  throw new UnprocessableEntityException({
    code: "EXPORT_ROW_LIMIT_EXCEEDED",
    maxRows: ASYNC_EXPORT_ROW_LIMIT,
    message: "Narrow the report filter before exporting.",
  });
}

@Injectable()
export class OoxmlWorkbookBuilder {
  async build(input: OoxmlWorkbookInput): Promise<Buffer> {
    exportModeForRowCount(input.rows.length);
    if (input.rows.length > SYNC_EXPORT_ROW_LIMIT) {
      return this.buildStreaming(input);
    }
    const workbook = new ExcelJS.Workbook();
    workbook.creator = "MagicMusicCRM";
    workbook.created = new Date();
    workbook.calcProperties.fullCalcOnLoad = true;
    const worksheet = workbook.addWorksheet(this.safeSheetName(input.sheetName));
    worksheet.columns = input.columns.map((column) => ({
      key: column.key,
      header: column.header,
      width: column.width ?? Math.max(12, column.header.length + 2),
    }));
    this.styleHeader(worksheet.getRow(1));
    for (const values of input.rows) {
      const row = worksheet.addRow([...values]);
      this.styleDataRow(row, input.columns);
    }
    worksheet.views = [{ state: "frozen", ySplit: 1 }];
    worksheet.autoFilter = {
      from: { row: 1, column: 1 },
      to: { row: 1, column: input.columns.length },
    };
    const buffer = Buffer.from(await workbook.xlsx.writeBuffer());
    await this.validate(buffer, input.columns.length);
    return buffer;
  }

  async validate(buffer: Buffer, expectedColumns?: number): Promise<void> {
    try {
      const workbook = new ExcelJS.Workbook();
      const arrayBuffer = Uint8Array.from(buffer).buffer;
      await workbook.xlsx.load(arrayBuffer);
      const worksheet = workbook.worksheets[0];
      if (!worksheet || worksheet.rowCount < 1) {
        throw new Error("Workbook has no worksheet data.");
      }
      if (
        expectedColumns !== undefined &&
        worksheet.columnCount !== expectedColumns
      ) {
        throw new Error("Workbook column count does not match the schema.");
      }
    } catch (error) {
      throw new UnprocessableEntityException({
        code: "INVALID_OOXML_WORKBOOK",
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }

  private async buildStreaming(input: OoxmlWorkbookInput): Promise<Buffer> {
    const output = new PassThrough();
    const chunks: Buffer[] = [];
    output.on("data", (chunk: Buffer | Uint8Array) => {
      chunks.push(Buffer.from(chunk));
    });
    const completed = new Promise<void>((resolve, reject) => {
      output.once("end", resolve);
      output.once("error", reject);
    });
    const workbook = new ExcelJS.stream.xlsx.WorkbookWriter({
      stream: output,
      useStyles: true,
      useSharedStrings: true,
    });
    const worksheet = workbook.addWorksheet(this.safeSheetName(input.sheetName));
    worksheet.columns = input.columns.map((column) => ({
      key: column.key,
      header: column.header,
      width: column.width ?? Math.max(12, column.header.length + 2),
    }));
    this.styleHeader(worksheet.getRow(1));
    worksheet.getRow(1).commit();
    for (const values of input.rows) {
      const row = worksheet.addRow([...values]);
      this.styleDataRow(row, input.columns);
      row.commit();
    }
    worksheet.commit();
    await workbook.commit();
    await completed;
    const buffer = Buffer.concat(chunks);
    await this.validate(buffer, input.columns.length);
    return buffer;
  }

  private styleHeader(row: ExcelJS.Row): void {
    row.font = { bold: true, color: { argb: "FFFFFFFF" } };
    row.fill = {
      type: "pattern",
      pattern: "solid",
      fgColor: { argb: "FF7B5B21" },
    };
    row.alignment = { vertical: "middle", horizontal: "center" };
  }

  private styleDataRow(
    row: ExcelJS.Row,
    columns: readonly OoxmlColumn[],
  ): void {
    columns.forEach((column, index) => {
      const cell = row.getCell(index + 1);
      if (column.type === "date") {
        cell.numFmt = "dd.mm.yyyy";
      } else if (column.type === "money") {
        cell.numFmt = '#,##0.00 [$₽-ru-RU]';
      } else if (column.type === "number" || column.type === "formula") {
        cell.numFmt = "#,##0.00";
      }
    });
  }

  private safeSheetName(value: string): string {
    const normalized = value.replace(/[\\/*?:[\]]/g, " ").trim();
    return (normalized || "Report").slice(0, 31);
  }
}
