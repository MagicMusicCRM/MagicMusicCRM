import { Logger } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { ClientStatusReadService } from "./client-status-read.service";
import { OoxmlWorkbookBuilder } from "./ooxml-workbook.builder";
import { ReportExportRequestDto } from "./dto/report-export.dto";
import { ReportExportService } from "./report-export.service";
import { ReportingReadService } from "./reporting-read.service";

describe("ReportExportService background worker", () => {
  const actor: ActorContext = { userId: "user-a", role: "director" };
  const dto: ReportExportRequestDto = {
    reportKey: "client_status",
    format: "csv",
  };

  const build = (query: jest.Mock, list = jest.fn()) =>
    new ReportExportService(
      { query } as unknown as DatabaseService,
      { list } as unknown as ClientStatusReadService,
      {} as ReportingReadService,
      {} as OoxmlWorkbookBuilder,
      { record: jest.fn().mockResolvedValue(undefined) } as unknown as AuditService,
    );

  it("contains claim failures inside the durable queue drain", async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce({
        rows: [
          {
            id: "11111111-1111-4111-8111-111111111111",
            actor_user_id: actor.userId,
            role: actor.role,
            filter_spec: dto,
            row_count: 1001,
          },
        ],
      })
      .mockRejectedValueOnce(new Error("database unavailable"));
    const logger = jest.spyOn(Logger.prototype, "error").mockImplementation();
    const service = build(query);

    await expect(
      (service as unknown as { drainQueuedJobs(): Promise<void> }).drainQueuedJobs(),
    ).resolves.toBeUndefined();

    expect(logger).toHaveBeenCalledWith(
      expect.stringContaining("claim failed: Error:database unavailable"),
    );
    logger.mockRestore();
  });

  it("marks a claimed export failed without leaking a rejected Promise", async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce({ rows: [{ id: "job-a" }] })
      .mockResolvedValueOnce({ rows: [] });
    const service = build(
      query,
      jest.fn().mockRejectedValue(new Error("report build failed")),
    );
    const logger = jest.spyOn(Logger.prototype, "error").mockImplementation();

    await expect(
      (
        service as unknown as {
          processJob(
            jobId: string,
            actor: ActorContext,
            dto: ReportExportRequestDto,
            rowCount: number,
          ): Promise<void>;
        }
      ).processJob("job-a", actor, dto, 1001),
    ).resolves.toBeUndefined();

    expect(query.mock.calls[1][0]).toContain("status = 'failed'");
    expect(logger).toHaveBeenCalledWith(
      expect.stringContaining("Report export job-a failed"),
    );
    logger.mockRestore();
  });

  it("recovers queued and stale processing jobs", async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const service = build(query);

    await (
      service as unknown as { drainQueuedJobs(): Promise<void> }
    ).drainQueuedJobs();

    expect(query.mock.calls[0][0]).toContain("job.status = 'queued'");
    expect(query.mock.calls[0][0]).toContain("interval '15 minutes'");
  });
});
