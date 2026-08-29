import {
  Injectable,
  Logger,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
} from "@nestjs/common";
import { randomUUID } from "crypto";
import { ActorContext, UserRole } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { AuditService } from "../audit/audit.service";
import {
  ClientStatusReadService,
  ClientStatusFilterSpec,
} from "./client-status-read.service";
import { ClientStatusFilterQuery } from "./dto/client-status-filter.query";
import {
  ReportExportFormat,
  ReportExportKey,
  ReportExportRequestDto,
} from "./dto/report-export.dto";
import {
  CSV_MIME,
  exportModeForRowCount,
  OoxmlCell,
  OoxmlColumn,
  OoxmlWorkbookBuilder,
  OoxmlWorkbookInput,
  XLSX_MIME,
} from "../common/ooxml-workbook.builder";
import { ReportingReadService } from "./reporting-read.service";

interface ExportJobRow {
  id: string;
  actor_user_id: string;
  report_key: ReportExportKey;
  format: ReportExportFormat;
  filter_spec: ReportExportRequestDto;
  row_count: number;
  status: "queued" | "processing" | "ready" | "failed" | "expired";
  filename: string | null;
  mime_type: string | null;
  content: Buffer | null;
  error_code: string | null;
  created_at: string;
  completed_at: string | null;
  expires_at: string;
}

interface BuiltExport {
  content: Buffer;
  filename: string;
  mimeType: string;
  rowCount: number;
}

export type ReportExportRequestResult =
  | ({ mode: "sync" } & BuiltExport)
  | {
      mode: "async";
      jobId: string;
      status: "queued";
      rowCount: number;
      expiresAt: string;
    };

@Injectable()
export class ReportExportService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(ReportExportService.name);
  private workerTimer?: ReturnType<typeof setInterval>;
  private startupTimer?: ReturnType<typeof setTimeout>;
  private workerRunning = false;

  constructor(
    private readonly database: DatabaseService,
    private readonly clientStatus: ClientStatusReadService,
    private readonly reporting: ReportingReadService,
    private readonly workbook: OoxmlWorkbookBuilder,
    private readonly audit: AuditService,
  ) {}

  onModuleInit(): void {
    const tick = () => {
      void this.drainQueuedJobs().catch((error: unknown) => {
        this.logger.error(
          `Report export worker tick failed: ${failureName(error)}`,
        );
      });
    };
    this.startupTimer = setTimeout(tick, 1_000);
    this.startupTimer.unref?.();
    this.workerTimer = setInterval(tick, 5_000);
    this.workerTimer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.startupTimer) clearTimeout(this.startupTimer);
    if (this.workerTimer) clearInterval(this.workerTimer);
  }

  async request(
    actor: ActorContext,
    dto: ReportExportRequestDto,
  ): Promise<ReportExportRequestResult> {
    const rowCount = await this.countRows(actor, dto);
    const mode = exportModeForRowCount(rowCount);
    if (mode === "sync") {
      const built = await this.build(actor, dto, rowCount);
      await this.recordAudit(actor, dto, rowCount, "sync");
      return { mode, ...built };
    }

    const id = randomUUID();
    const created = await this.database.query<{ expires_at: string }>(
      `
        insert into app.report_export_jobs (
          id,
          actor_user_id,
          report_key,
          format,
          filter_spec,
          row_count
        )
        values ($1, $2, $3, $4, $5::jsonb, $6)
        returning expires_at
      `,
      [
        id,
        actor.userId,
        dto.reportKey,
        dto.format,
        JSON.stringify(dto),
        rowCount,
      ],
    );
    setImmediate(() => {
      void this.processJob(id, actor, dto, rowCount).catch((error: unknown) => {
        this.logger.error(
          `Report export ${id} could not be claimed: ${failureName(error)}`,
        );
      });
    });
    return {
      mode,
      jobId: id,
      status: "queued",
      rowCount,
      expiresAt: created.rows[0]!.expires_at,
    };
  }

  async financeWorkbook(
    actor: ActorContext,
    filter: Pick<ReportExportRequestDto, "from" | "to" | "branchId">,
  ): Promise<Buffer> {
    const dto: ReportExportRequestDto = {
      reportKey: "school_finance",
      format: "xlsx",
      ...filter,
    };
    const rowCount = await this.countRows(actor, dto);
    return (await this.build(actor, dto, rowCount)).content;
  }

  async getJob(actor: ActorContext, jobId: string) {
    const job = await this.loadOwnedJob(actor, jobId);
    return {
      id: job.id,
      reportKey: job.report_key,
      format: job.format,
      rowCount: Number(job.row_count),
      status: this.effectiveStatus(job),
      filename: job.filename,
      errorCode: job.error_code,
      createdAt: job.created_at,
      completedAt: job.completed_at,
      expiresAt: job.expires_at,
      downloadReady:
        job.status === "ready" && new Date(job.expires_at) > new Date(),
    };
  }

  async download(actor: ActorContext, jobId: string): Promise<BuiltExport> {
    const job = await this.loadOwnedJob(actor, jobId);
    if (
      job.status !== "ready" ||
      !job.content ||
      !job.filename ||
      !job.mime_type ||
      new Date(job.expires_at) <= new Date()
    ) {
      throw new NotFoundException({
        code: "REPORT_EXPORT_NOT_READY",
        message: "Export file is not available.",
      });
    }
    return {
      content: job.content,
      filename: job.filename,
      mimeType: job.mime_type,
      rowCount: Number(job.row_count),
    };
  }

  private async processJob(
    jobId: string,
    actor: ActorContext,
    dto: ReportExportRequestDto,
    rowCount: number,
  ): Promise<void> {
    const claimed = await this.database.query<{ id: string }>(
      `
        update app.report_export_jobs
           set status = 'processing',
               started_at = now()
         where id = $1
           and (
             status = 'queued'
             or (status = 'processing' and started_at < now() - interval '15 minutes')
           )
         returning id
      `,
      [jobId],
    );
    if (claimed.rows.length === 0) return;
    try {
      const built = await this.build(actor, dto, rowCount);
      await this.database.query(
        `
          update app.report_export_jobs
             set status = 'ready',
                 filename = $2,
                 mime_type = $3,
                 content = $4,
                 completed_at = now()
           where id = $1
        `,
        [jobId, built.filename, built.mimeType, built.content],
      );
      await this.recordAudit(actor, dto, rowCount, "async");
    } catch (error) {
      this.logger.error(
        `Report export ${jobId} failed: ${failureName(error)}`,
      );
      try {
        await this.database.query(
          `
            update app.report_export_jobs
               set status = 'failed',
                   error_code = 'REPORT_EXPORT_BUILD_FAILED',
                   completed_at = now()
             where id = $1
          `,
          [jobId],
        );
      } catch (persistError) {
        this.logger.error(
          `Report export ${jobId} failure state was not persisted: ${failureName(persistError)}`,
        );
      }
    }
  }

  private async drainQueuedJobs(): Promise<void> {
    if (this.workerRunning) return;
    this.workerRunning = true;
    try {
      const queued = await this.database.query<{
        id: string;
        actor_user_id: string;
        role: UserRole;
        filter_spec: ReportExportRequestDto;
        row_count: number;
      }>(
        `
          select job.id, job.actor_user_id, app_user.role,
                 job.filter_spec, job.row_count
          from app.report_export_jobs job
          join app.users app_user
            on app_user.id = job.actor_user_id
           and app_user.deleted_at is null
          where job.status = 'queued'
             or (
               job.status = 'processing'
               and job.started_at < now() - interval '15 minutes'
             )
          order by job.created_at asc
          limit 5
        `,
      );
      for (const job of queued.rows) {
        try {
          await this.processJob(
            job.id,
            { userId: job.actor_user_id, role: job.role },
            job.filter_spec,
            Number(job.row_count),
          );
        } catch (error) {
          this.logger.error(
            `Report export ${job.id} claim failed: ${failureName(error)}`,
          );
        }
      }
    } finally {
      this.workerRunning = false;
    }
  }

  private async countRows(
    actor: ActorContext,
    dto: ReportExportRequestDto,
  ): Promise<number> {
    if (dto.reportKey === "school_finance") {
      const report = await this.reporting.schoolFinance(actor, dto);
      return report.rows.length;
    }
    const page = await this.clientStatus.list(actor, {
      ...new ClientStatusFilterQuery(),
      ...this.statusFilter(dto),
      limit: 1,
      offset: 0,
    });
    return page.total;
  }

  private async build(
    actor: ActorContext,
    dto: ReportExportRequestDto,
    rowCount: number,
  ): Promise<BuiltExport> {
    const input =
      dto.reportKey === "school_finance"
        ? await this.financeInput(actor, dto)
        : await this.clientStatusInput(actor, dto, rowCount);
    const date = new Date().toISOString().slice(0, 10);
    const baseName =
      dto.reportKey === "school_finance"
        ? `school-finance-${date}`
        : `client-status-${date}`;
    if (dto.format === "csv") {
      return {
        content: Buffer.from(`\uFEFF${this.toCsv(input)}`, "utf8"),
        filename: `${baseName}.csv`,
        mimeType: CSV_MIME,
        rowCount,
      };
    }
    return {
      content: await this.workbook.build(input),
      filename: `${baseName}.xlsx`,
      mimeType: XLSX_MIME,
      rowCount,
    };
  }

  private async financeInput(
    actor: ActorContext,
    dto: ReportExportRequestDto,
  ): Promise<OoxmlWorkbookInput> {
    const report = await this.reporting.schoolFinance(actor, dto);
    const columns: readonly OoxmlColumn[] = [
      { key: "month", header: "Месяц", type: "date", width: 14 },
      { key: "lessons", header: "Занятия", type: "number", width: 12 },
      {
        key: "success",
        header: "Успешно завершены",
        type: "number",
        width: 20,
      },
      { key: "revenue", header: "Выручка", type: "money", width: 16 },
      { key: "expenses", header: "Расходы", type: "money", width: 16 },
      { key: "net", header: "Итого", type: "formula", width: 16 },
    ];
    return {
      sheetName: "Финансы",
      columns,
      rows: report.rows.map((row, index) => {
        const excelRow = index + 2;
        const revenue = Number(BigInt(row.revenueMinor)) / 100;
        const expenses = Number(BigInt(row.expensesMinor)) / 100;
        return [
          new Date(`${row.monthStart}T00:00:00.000Z`),
          row.totalLessons,
          row.successfulLessons,
          revenue,
          expenses,
          { formula: `D${excelRow}-E${excelRow}`, result: revenue - expenses },
        ];
      }),
    };
  }

  private async clientStatusInput(
    actor: ActorContext,
    dto: ReportExportRequestDto,
    rowCount: number,
  ): Promise<OoxmlWorkbookInput> {
    const rows: OoxmlCell[][] = [];
    for (let offset = 0; offset < rowCount; offset += 200) {
      const page = await this.clientStatus.list(actor, {
        ...new ClientStatusFilterQuery(),
        ...this.statusFilter(dto),
        limit: 200,
        offset,
      });
      for (const item of page.items) {
        rows.push([
          item.type,
          item.displayName,
          item.statusLabel,
          item.branchId ?? "",
          new Date(item.createdAt),
        ]);
      }
    }
    return {
      sheetName: "Статусы клиентов",
      columns: [
        { key: "type", header: "Тип", type: "string", width: 12 },
        { key: "name", header: "Клиент", type: "string", width: 28 },
        { key: "status", header: "Статус", type: "string", width: 22 },
        { key: "branch", header: "Филиал ID", type: "string", width: 38 },
        { key: "created", header: "Создан", type: "date", width: 14 },
      ],
      rows,
    };
  }

  private statusFilter(dto: ReportExportRequestDto): ClientStatusFilterSpec {
    return {
      version: 1,
      ...(dto.clientType ? { clientType: dto.clientType } : {}),
      ...(dto.status ? { status: dto.status } : {}),
      ...(dto.branchId ? { branchId: dto.branchId } : {}),
      ...(dto.from ? { from: dto.from } : {}),
      ...(dto.to ? { to: dto.to } : {}),
      ...(dto.q ? { q: dto.q } : {}),
    };
  }

  private toCsv(input: OoxmlWorkbookInput): string {
    const escape = (value: OoxmlCell) => {
      const raw =
        value instanceof Date
          ? value.toISOString()
          : typeof value === "object" && value !== null && "formula" in value
            ? String(value.result)
            : String(value ?? "");
      return /[";\r\n]/.test(raw) ? `"${raw.replace(/"/g, '""')}"` : raw;
    };
    return (
      [
        input.columns.map((column) => escape(column.header)).join(";"),
        ...input.rows.map((row) => row.map(escape).join(";")),
      ].join("\r\n") + "\r\n"
    );
  }

  private async loadOwnedJob(
    actor: ActorContext,
    jobId: string,
  ): Promise<ExportJobRow> {
    const result = await this.database.query<ExportJobRow>(
      `
        select *
        from app.report_export_jobs
        where id = $1
          and actor_user_id = $2
        limit 1
      `,
      [jobId, actor.userId],
    );
    const job = result.rows[0];
    if (!job) {
      throw new NotFoundException({
        code: "REPORT_EXPORT_NOT_FOUND",
        message: "Export job was not found.",
      });
    }
    return job;
  }

  private effectiveStatus(job: ExportJobRow): ExportJobRow["status"] {
    if (job.status === "ready" && new Date(job.expires_at) <= new Date()) {
      return "expired";
    }
    return job.status;
  }

  private recordAudit(
    actor: ActorContext,
    dto: ReportExportRequestDto,
    rowCount: number,
    mode: "sync" | "async",
  ) {
    return this.audit.record({
      actor,
      action: "analytics.report_exported",
      entityType: "report",
      metadata: {
        reportKey: dto.reportKey,
        format: dto.format,
        rowCount,
        mode,
      },
    });
  }
}

function failureName(error: unknown): string {
  if (!(error instanceof Error)) return "unknown";
  return `${error.constructor.name}:${error.message}`.slice(0, 240);
}
