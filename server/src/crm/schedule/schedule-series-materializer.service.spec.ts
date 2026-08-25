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
});
