import { DatabaseService } from "../../db/database.service";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import { ScheduleSeriesMaterializerService } from "./schedule-series-materializer.service";

describe("ScheduleSeriesMaterializerService", () => {
  it("selects live series using each branch timezone", async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const service = new ScheduleSeriesMaterializerService(
      {
        query,
        transaction: jest.fn(),
      } as unknown as DatabaseService,
      {
        validate: jest.fn().mockResolvedValue({ valid: true, violations: [] }),
      } as unknown as ScheduleConstraintEngine,
    );

    await expect(service.extendAllSeriesHorizon()).resolves.toEqual({
      series: 0,
      created: 0,
      failed: 0,
    });

    const sql = String(query.mock.calls[0]?.[0]);
    expect(sql).toContain(
      "join app.branches branch on branch.id = s.branch_id",
    );
    expect(sql).toContain(
      "coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow')",
    );
    expect(sql).not.toContain("now() at time zone 'Europe/Moscow'");
  });

  it("starts confirmed plan materialization at valid_from for historical periods", async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const service = new ScheduleSeriesMaterializerService(
      {} as DatabaseService,
      {
        validate: jest.fn().mockResolvedValue({ valid: true, violations: [] }),
      } as unknown as ScheduleConstraintEngine,
    );
    const client = { query };

    await (
      service.materializePlanSeries as never as (
        client: unknown,
        seriesId: string,
        options: { includePast: boolean },
      ) => Promise<number>
    )(client, "series-a", { includePast: true });

    const sql = query.mock.calls.map((call) => String(call[0])).join("\n");
    expect(sql).toContain(
      "case when $4::boolean then s.valid_from else greatest(s.valid_from, s.local_today) end",
    );
    expect(sql).toContain(
      "case when $4::boolean then s.valid_from else greatest(",
    );
    expect(query.mock.calls.some((call) => call[1]?.includes(true))).toBe(true);
  });
});
