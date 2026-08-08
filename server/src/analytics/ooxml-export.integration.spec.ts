import { ConfigService } from "@nestjs/config";
import {
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { randomUUID } from "crypto";
import { mkdir, writeFile } from "fs/promises";
import { dirname, resolve } from "path";
import * as ExcelJS from "exceljs";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { AuditService } from "../audit/audit.service";
import { ClientStatusReadService } from "./client-status-read.service";
import {
  ASYNC_EXPORT_ROW_LIMIT,
  exportModeForRowCount,
  OoxmlWorkbookBuilder,
  SYNC_EXPORT_ROW_LIMIT,
  XLSX_MIME,
} from "./ooxml-workbook.builder";
import { ReportExportService } from "./report-export.service";
import { ReportingReadService } from "./reporting-read.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const parsedDatabaseUrl = new URL(databaseUrl);
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(parsedDatabaseUrl.hostname)
) {
  throw new Error("OOXML export tests require local PostgreSQL.");
}

jest.setTimeout(90_000);

describe("v4 OOXML export", () => {
  const builder = new OoxmlWorkbookBuilder();
  let database: DatabaseService;
  let actors: {
    owner: ActorContext;
    stranger: ActorContext;
    userIds: string[];
  };

  beforeAll(async () => {
    database = new DatabaseService(
      new ConfigService({ DATABASE_URL: databaseUrl }),
    );
    await cleanupStale(database);
    const users = await database.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, 'director', now()), ($2, 'director', now())
        returning id
      `,
      [
        `v4-ooxml-${randomUUID()}-owner@example.test`,
        `v4-ooxml-${randomUUID()}-stranger@example.test`,
      ],
    );
    actors = {
      owner: { userId: users.rows[0]!.id, role: "director" },
      stranger: { userId: users.rows[1]!.id, role: "director" },
      userIds: users.rows.map((row) => row.id),
    };
  });

  afterAll(async () => {
    if (actors) {
      await database.query(
        "delete from app.report_export_jobs where actor_user_id = any($1::uuid[])",
        [actors.userIds],
      );
      await database.query("delete from app.users where id = any($1::uuid[])", [
        actors.userIds,
      ]);
    }
    await database.onModuleDestroy();
  });

  it("builds a valid workbook with Unicode, date, money and formula cells", async () => {
    const buffer = await builder.build({
      sheetName: "Финансы школы",
      columns: [
        { key: "name", header: "Клиент", type: "string" },
        { key: "date", header: "Дата", type: "date" },
        { key: "money", header: "Сумма", type: "money" },
        { key: "formula", header: "Итого", type: "formula" },
      ],
      rows: [
        [
          "Алина — Юникод",
          new Date("2026-07-30T00:00:00.000Z"),
          6400,
          { formula: "C2*2", result: 12800 },
        ],
      ],
    });
    expect(buffer.subarray(0, 2).toString("ascii")).toBe("PK");
    await builder.validate(buffer, 4);

    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(Uint8Array.from(buffer).buffer);
    const sheet = workbook.worksheets[0]!;
    expect(sheet.getCell("A2").value).toBe("Алина — Юникод");
    expect(sheet.getCell("B2").value).toBeInstanceOf(Date);
    expect(sheet.getCell("C2").numFmt).toContain("₽");
    expect(sheet.getCell("D2").value).toEqual({
      formula: "C2*2",
      result: 12800,
    });

    const fixturePath = resolve(process.cwd(), "..", "build", "v4-report.xlsx");
    await mkdir(dirname(fixturePath), { recursive: true });
    await writeFile(fixturePath, buffer);
  });

  it("enforces sync/async/maximum row contracts", () => {
    expect(exportModeForRowCount(SYNC_EXPORT_ROW_LIMIT)).toBe("sync");
    expect(exportModeForRowCount(SYNC_EXPORT_ROW_LIMIT + 1)).toBe("async");
    expect(exportModeForRowCount(ASYNC_EXPORT_ROW_LIMIT)).toBe("async");
    expect(() => exportModeForRowCount(ASYNC_EXPORT_ROW_LIMIT + 1)).toThrow(
      UnprocessableEntityException,
    );
  });

  it("exports an Excel-friendly UTF-8 CSV with Cyrillic intact", async () => {
    const clientStatus = {
      list: jest.fn(async () => ({
        total: 1,
        items: [
          {
            type: "student",
            id: "student-1",
            displayName: "Алёна Смирнова",
            status: "active",
            statusLabel: "Занимается",
            branchId: null,
            createdAt: "2026-08-08T00:00:00.000Z",
          },
        ],
      })),
    } as unknown as ClientStatusReadService;
    const service = new ReportExportService(
      database,
      clientStatus,
      {} as ReportingReadService,
      builder,
      {
        record: jest.fn().mockResolvedValue(undefined),
      } as unknown as AuditService,
    );

    const result = await service.request(actors.owner, {
      reportKey: "client_status",
      format: "csv",
    });

    expect(result.mode).toBe("sync");
    if (result.mode !== "sync") throw new Error("Expected sync export.");
    expect([...result.content.subarray(0, 3)]).toEqual([0xef, 0xbb, 0xbf]);
    expect(result.content.toString("utf8")).toContain(
      "\uFEFFТип;Клиент;Статус;Филиал ID;Создан\r\nstudent;Алёна Смирнова;Занимается;",
    );
  });

  it("keeps async downloads private and produces a validated streaming XLSX", async () => {
    const rowCount = SYNC_EXPORT_ROW_LIMIT + 1;
    const clientStatus = {
      list: jest.fn(
        async (
          _actor: ActorContext,
          query: { limit: number; offset: number },
        ) => {
          const count = Math.max(
            0,
            Math.min(query.limit, rowCount - query.offset),
          );
          return {
            total: rowCount,
            items: Array.from({ length: count }, (_, index) => ({
              type: "lead",
              id: `${query.offset + index}`,
              displayName: `Клиент ${query.offset + index}`,
              status: "new",
              statusLabel: "Новый",
              branchId: null,
              createdAt: "2026-07-30T00:00:00.000Z",
            })),
          };
        },
      ),
    } as unknown as ClientStatusReadService;
    const reporting = {} as ReportingReadService;
    const audit = {
      record: jest.fn().mockResolvedValue(undefined),
    } as unknown as AuditService;
    const service = new ReportExportService(
      database,
      clientStatus,
      reporting,
      builder,
      audit,
    );

    const requested = await service.request(actors.owner, {
      reportKey: "client_status",
      format: "xlsx",
    });
    expect(requested).toMatchObject({
      mode: "async",
      status: "queued",
      rowCount,
    });
    if (requested.mode !== "async") throw new Error("Expected async export.");

    await expect(
      service.getJob(actors.stranger, requested.jobId),
    ).rejects.toBeInstanceOf(NotFoundException);

    let status = "queued";
    for (let attempt = 0; attempt < 80 && status !== "ready"; attempt++) {
      await new Promise((resolveDelay) => setTimeout(resolveDelay, 100));
      status = (await service.getJob(actors.owner, requested.jobId)).status;
    }
    expect(status).toBe("ready");
    const download = await service.download(actors.owner, requested.jobId);
    expect(download.mimeType).toBe(XLSX_MIME);
    expect(download.filename.endsWith(".xlsx")).toBe(true);
    await builder.validate(download.content, 5);
  });
});

async function cleanupStale(database: DatabaseService) {
  const users = await database.query<{ id: string }>(
    "select id from app.users where email like 'v4-ooxml-%@example.test'",
  );
  const userIds = users.rows.map((row) => row.id);
  if (userIds.length === 0) return;
  await database.query(
    "delete from app.report_export_jobs where actor_user_id = any($1::uuid[])",
    [userIds],
  );
  await database.query(
    "delete from app.audit_events where actor_user_id = any($1::uuid[])",
    [userIds],
  );
  await database.query("delete from app.users where id = any($1::uuid[])", [
    userIds,
  ]);
}
