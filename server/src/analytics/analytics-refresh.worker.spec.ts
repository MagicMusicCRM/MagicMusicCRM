// server/src/analytics/analytics-refresh.worker.spec.ts
import { AnalyticsRefreshWorker } from "./analytics-refresh.worker";
import { DatabaseService } from "../db/database.service";
import { Logger } from "@nestjs/common";

describe("AnalyticsRefreshWorker", () => {
  const build = (claimRows: Record<string, unknown>[]) => {
    const query = jest.fn();
    query.mockResolvedValueOnce({ rows: claimRows }); // claim insert
    query.mockResolvedValue({ rows: [] });            // refreshes + finalize
    const worker = new AnalyticsRefreshWorker({ query } as unknown as DatabaseService);
    return { worker, query };
  };

  it("refreshes the matviews when it wins the claim", async () => {
    const { worker, query } = build([{ id: "run-1" }]);
    const result = await worker.refreshNow();
    expect(result).toEqual({ refreshed: true });
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("insert into app.analytics_refresh_runs");
    expect(sql).toContain("refresh materialized view app.mv_finance_monthly");
    expect(sql).toContain("refresh materialized view app.mv_teacher_performance");
    expect(sql).toContain("refresh materialized view app.mv_room_load");
    expect(sql).toContain("update app.analytics_refresh_runs");
  });

  it("skips when another run holds the claim (no row returned)", async () => {
    const { worker, query } = build([]); // claim insert returns nothing
    const result = await worker.refreshNow();
    expect(result).toEqual({ refreshed: false });
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).not.toContain("refresh materialized view");
  });

  it("logs periodic refresh failures instead of swallowing them", async () => {
    jest.useFakeTimers();
    const logger = jest.spyOn(Logger.prototype, "error").mockImplementation();
    const worker = new AnalyticsRefreshWorker({
      query: jest.fn().mockRejectedValue(new Error("database unavailable")),
    } as unknown as DatabaseService);

    worker.onModuleInit();
    await jest.advanceTimersByTimeAsync(5 * 60_000);

    expect(logger).toHaveBeenCalledWith(
      "Analytics refresh failed: Error:database unavailable",
    );
    worker.onModuleDestroy();
    logger.mockRestore();
    jest.useRealTimers();
  });
});
