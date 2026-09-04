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

  it("rechecks the exact frozen plan clients after every materialization lock", async () => {
    const events: string[] = [];
    let activeReferences: Array<{ type: string; id: string }> = [];
    const candidates = [{
      series_date: "2026-09-07",
      plan_id: "plan-a",
      group_id: "group-a",
      teacher_id: "teacher-a",
      branch_id: "branch-a",
      room_id: "room-a",
      starts_at: "2026-09-07T07:00:00.000Z",
      ends_at: "2026-09-07T08:00:00.000Z",
      client_refs: [
        { type: "student", id: "student-b" },
        { type: "student", id: "student-a" },
      ],
    }];
    const query = jest.fn(async (sql: string, values?: unknown[]) => {
      if (sql.includes("with recursive target") && sql.includes("client_refs")) {
        events.push("candidate-read");
        return { rows: candidates };
      }
      if (sql.includes("pg_advisory_xact_lock")) {
        events.push(`lock:${String(values?.[0])}`);
        return { rows: [] };
      }
      if (sql.includes("jsonb_to_recordset")) {
        events.push("active-client-recheck");
        activeReferences = JSON.parse(String(values?.[0]));
        return { rows: [] };
      }
      if (sql.includes("insert into app.lessons")) {
        events.push("lesson-insert");
        return { rows: [] };
      }
      return { rows: [] };
    });
    const service = new ScheduleSeriesMaterializerService(
      {} as DatabaseService,
      {
        validate: jest.fn().mockResolvedValue({ valid: true, violations: [] }),
      } as unknown as ScheduleConstraintEngine,
    );

    await service.materializePlanSeries({ query } as never, "series-a");

    expect(activeReferences).toEqual([
      { type: "student", id: "student-a" },
      { type: "student", id: "student-b" },
    ]);
    const lastLock = events.reduce(
      (index, event, current) => event.startsWith("lock:") ? current : index,
      -1,
    );
    expect(events.indexOf("active-client-recheck")).toBeGreaterThan(lastLock);
    expect(events.indexOf("lesson-insert")).toBeGreaterThan(
      events.indexOf("active-client-recheck"),
    );
  });
});
