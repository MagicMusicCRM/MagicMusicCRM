import { BadRequestException, ConflictException } from "@nestjs/common";
import { AuditService } from "../../audit/audit.service";
import { DatabaseService } from "../../db/database.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import { ScheduleSeriesMaterializerService } from "./schedule-series-materializer.service";
import { ScheduleSeriesService } from "./schedule-series.service";

describe("ScheduleSeriesService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  afterEach(() => jest.useRealTimers());

  const buildDeps = () => ({
    audit: { record: jest.fn().mockResolvedValue(undefined) },
    constraints: {
      validate: jest.fn().mockResolvedValue({ valid: true, violations: [] }),
    },
    policy: {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
    },
  });

  const constructSeries = (
    query: jest.Mock,
    deps: ReturnType<typeof buildDeps>,
  ) => {
    const database = {
      query,
      transaction: (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    } as unknown as DatabaseService;
    return new ScheduleSeriesService(
      database,
      deps.audit as unknown as AuditService,
      deps.policy as unknown as CrmPolicy,
      { emitCrmChanged: () => undefined } as unknown as RealtimeBus,
      new ScheduleSeriesMaterializerService(
        database,
        deps.constraints as unknown as ScheduleConstraintEngine,
      ),
    );
  };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const deps = buildDeps();
    const series = constructSeries(query, deps);
    return { series, query, ...deps };
  };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const queuedResults = [...results];
    let legacyPreRead: { rows: Record<string, unknown>[] } | undefined;
    const query = jest.fn().mockImplementation((sql: unknown) => {
      if (String(sql).includes("pg_advisory_xact_lock")) {
        return Promise.resolve({ rows: [] });
      }
      if (String(sql).includes("jsonb_to_recordset")) {
        return Promise.resolve({ rows: [] });
      }
      if (
        String(sql).includes("from app.schedule_series s") &&
        String(sql).includes("client_refs")
      ) {
        if (String(sql).includes("for update of s")) {
          return Promise.resolve(legacyPreRead);
        }
        legacyPreRead = queuedResults.shift();
        return Promise.resolve(legacyPreRead);
      }
      return Promise.resolve(queuedResults.shift());
    });
    const deps = buildDeps();
    const series = constructSeries(query, deps);
    return { series, query, ...deps };
  };

  it("uses Moscow business dates across the UTC midnight boundary", () => {
    jest.useFakeTimers();
    try {
      jest.setSystemTime(new Date("2026-07-17T21:30:00.000Z"));
      const service = Object.create(
        ScheduleSeriesService.prototype,
      ) as ScheduleSeriesService;
      const businessDate = service as unknown as {
        moscowDate(offsetDays?: number): string;
      };

      expect(businessDate.moscowDate()).toBe("2026-07-18");
      expect(businessDate.moscowDate(1)).toBe("2026-07-19");
    } finally {
      jest.useRealTimers();
    }
  });

  it("rejects past edit and stop cutoffs before opening a transaction", async () => {
    jest.useFakeTimers();
    try {
      jest.setSystemTime(new Date("2026-07-18T09:00:00.000Z"));
      const query = jest.fn();
      const service = new ScheduleSeriesService(
        { query, transaction: jest.fn() } as unknown as DatabaseService,
        { record: jest.fn() } as unknown as AuditService,
        { assertCanWriteCrm: jest.fn() } as unknown as CrmPolicy,
        { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
        {} as ScheduleSeriesMaterializerService,
      );

      await expect(
        service.updateScheduleSeries(actor, "series-a", {
          effectiveFrom: "2026-07-17",
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      await expect(
        service.deleteScheduleSeries(actor, "series-a", "2026-07-17"),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(query).not.toHaveBeenCalled();
    } finally {
      jest.useRealTimers();
    }
  });

  it("rejects legacy edit and stop mutations for plan-owned series", async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date("2026-07-18T09:00:00.000Z"));
    const planOwnedRow = {
      id: "series-a",
      plan_id: "plan-a",
      superseded_by: null,
      valid_from: "2026-07-15",
      valid_until: null,
    };
    const update = createServiceWithQueryResults([{ rows: [planOwnedRow] }]);
    const stop = createServiceWithQueryResults([{ rows: [planOwnedRow] }]);

    await expect(
      update.series.updateScheduleSeries(actor, "series-a", {
        effectiveFrom: "2026-08-01",
      }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "SCHEDULE_PLAN_MUTATION_REQUIRED",
      }),
    });
    await expect(
      stop.series.deleteScheduleSeries(actor, "series-a", "2026-08-01"),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "SCHEDULE_PLAN_MUTATION_REQUIRED",
      }),
    });
    expect(
      update.query.mock.calls.some((call) =>
        String(call[0]).includes("update app.schedule_series"),
      ),
    ).toBe(false);
    expect(
      stop.query.mock.calls.some((call) =>
        String(call[0]).includes("update app.schedule_series"),
      ),
    ).toBe(false);
  });

  it.each([
    ["student", { studentId: "student-a" }],
    ["group", { groupId: "group-a" }],
    ["lead", { clientRef: { type: "lead" as const, id: "lead-a" } }],
  ])("rejects legacy %s series creation", async (_subject, subject) => {
    const { series, query } = createServiceWithQueryResults([]);

    await expect(
      series.createScheduleSeries(actor, {
        ...subject,
        weekday: 1,
        beginTime: "10:00",
        validFrom: "2026-09-01",
      }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "SCHEDULE_PLAN_MUTATION_REQUIRED",
      }),
    });
    expect(query).not.toHaveBeenCalled();
  });
  it("keeps schedule-series DATE values timezone invariant", async () => {
    const { series, query } = createService([
      {
        id: "series-date",
        student_id: "student-a",
        group_id: null,
        teacher_id: "teacher-a",
        room_id: null,
        branch_id: null,
        weekday: 3,
        begin_time: "15:00:00",
        duration_minutes: 60,
        valid_from: "2026-07-15",
        valid_until: "2026-12-31",
        notes: null,
        created_at: "2026-07-01T10:00:00.000Z",
        updated_at: "2026-07-01T10:00:00.000Z",
      },
    ]);

    const result = await series.listScheduleSeries(actor, {});

    expect(result.items[0]).toMatchObject({
      validFrom: "2026-07-15",
      validUntil: "2026-12-31",
    });
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("s.valid_from::text as valid_from");
    expect(sql).toContain("s.valid_until::text as valid_until");
  });

  it("applies a series edit, preserves exceptions and explicitly clears a finite end", async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date("2026-07-18T09:00:00.000Z"));
    const { series, query } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "series-a",
            student_id: "student-a",
            group_id: null,
            teacher_id: "teacher-a",
            room_id: "room-a",
            branch_id: "branch-a",
            weekday: 2,
            begin_time: "15:00:00",
            duration_minutes: 60,
            valid_from: "2026-07-15",
            valid_until: "2026-12-31",
            notes: null,
            created_at: "2026-07-10",
            updated_at: "2026-07-10",
          },
        ],
      },
      { rows: [] }, // close old series
      { rows: [{ id: "series-b" }] }, // continuation insert
      { rows: [] }, // move future exceptions to the continuation
      { rows: [] }, // remove future untouched lessons
      { rows: [] }, // mark the old series as superseded
      { rows: [] }, // recurring candidates before locks
      { rows: [] }, // recurring candidates after locks
      { rows: [] }, // materialize continuation
    ]);

    await expect(
      series.updateScheduleSeries(actor, "series-a", {
        teacherId: "teacher-b",
        beginTime: "16:00",
        effectiveFrom: "2026-08-01",
        validUntil: null,
      }),
    ).resolves.toEqual({
      id: "series-b",
      previousId: "series-a",
      lessonsCreated: 0,
    });

    // Будущие занятия снимаются ТОЛЬКО нетронутые: scheduled и не перенесённые.
    const removeCall = query.mock.calls.find((call) =>
      String(call[0]).includes("set deleted_at = now()"),
    );
    const removeSql = String(removeCall?.[0]);
    expect(removeSql).toContain("original_scheduled_at is null");
    expect(removeSql).toContain("status = 'scheduled'");
    expect(removeSql).toContain("update app.lesson_reservations");
    expect(removeSql).toContain("state = 'released'");
    expect(removeCall?.[1]).toEqual(["series-a", "2026-08-01"]);
    const exceptionMove = query.mock.calls.find((call) =>
      String(call[0]).includes("set series_id = $2"),
    );
    expect(String(exceptionMove?.[0])).toContain("deleted_at is not null");
    expect(String(exceptionMove?.[0])).toContain(
      "original_scheduled_at is not null",
    );
    expect(exceptionMove?.[1]).toEqual(["series-a", "series-b", "2026-08-01"]);
    expect(query.mock.calls.indexOf(exceptionMove!)).toBeLessThan(
      query.mock.calls.indexOf(removeCall!),
    );
    // Продолжение наследует незатронутые параметры и берёт новые.
    const continuationCall = query.mock.calls.find((call) =>
      String(call[0]).includes("insert into app.schedule_series"),
    );
    expect(continuationCall?.[1]).toEqual([
      null,
      null,
      "student-a",
      null,
      "teacher-b",
      "room-a",
      "branch-a",
      2,
      "16:00",
      60,
      "2026-08-01",
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      "manager-a",
    ]);
    expect(
      query.mock.calls.some((call) => String(call[0]).includes("for update")),
    ).toBe(true);
    expect(query.mock.calls[0]?.[1]).toEqual([
      "commerce:multi-lesson-settlement",
    ]);
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("set superseded_by = $2"),
      ),
    ).toBe(true);
  });

  it("keeps a future-stopped series live so the worker reaches the cutoff", async () => {
    const responses = [
      { rows: [{ id: "series-a", superseded_by: null }] },
      { rows: [], rowCount: 1 },
      { rows: [], rowCount: 0 },
    ];
    const query = jest.fn().mockImplementation((sql: unknown) => {
      if (String(sql).includes("pg_advisory_xact_lock")) {
        return Promise.resolve({ rows: [] });
      }
      return Promise.resolve(responses.shift());
    });
    const series = constructSeries(query, buildDeps());

    await expect(
      series.deleteScheduleSeries(actor, "series-a", "2026-12-01"),
    ).resolves.toEqual({ id: "series-a", stoppedFrom: "2026-12-01" });

    const seriesUpdate = query.mock.calls.find((call) =>
      String(call[0]).includes("update app.schedule_series"),
    );
    expect(String(seriesUpdate?.[0])).toContain("deleted_at = case");
    expect(String(seriesUpdate?.[0])).toContain(
      "now() at time zone 'Europe/Moscow'",
    );
    expect(String(seriesUpdate?.[0])).toContain("else deleted_at");
  });

  it("stops series occurrences by their actual Moscow date, including moved lessons", async () => {
    const responses = [
      { rows: [{ id: "series-a", superseded_by: null }] },
      { rows: [], rowCount: 1 },
      { rows: [], rowCount: 2 },
    ];
    const query = jest.fn().mockImplementation((sql: unknown) => {
      if (String(sql).includes("pg_advisory_xact_lock")) {
        return Promise.resolve({ rows: [] });
      }
      return Promise.resolve(responses.shift());
    });
    const series = constructSeries(query, buildDeps());

    await series.deleteScheduleSeries(actor, "series-a", "2026-12-01");

    const lessonUpdate = query.mock.calls.find((call) =>
      String(call[0]).includes("update app.lessons"),
    );
    const sql = String(lessonUpdate?.[0]);
    expect(sql).toContain(
      "(scheduled_at at time zone 'Europe/Moscow')::date >= $2::date",
    );
    expect(sql).toContain("status = 'scheduled'");
    expect(sql).toContain("update app.lesson_reservations");
    expect(sql).toContain("state = 'released'");
    expect(sql).not.toContain("series_date >= $2::date");
    expect(sql).not.toContain("original_scheduled_at is null");
    expect(lessonUpdate?.[1]).toEqual(["series-a", "2026-12-01"]);
  });

  it("locks legacy client and old plus requested resources before the series row", async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date("2026-07-18T09:00:00.000Z"));
    const events: string[] = [];
    let continuationValues: unknown[] | undefined;
    const snapshot = {
      id: "series-a",
      plan_id: null,
      client_type: "lead" as const,
      client_id: "lead-a",
      student_id: null,
      group_id: null,
      teacher_id: "teacher-a",
      room_id: "room-a",
      branch_id: "branch-a",
      weekday: 2,
      begin_time: "15:00:00",
      duration_minutes: 60,
      valid_from: "2026-07-15",
      valid_until: "2026-12-31",
      notes: null,
      superseded_by: null,
      deleted_at: null,
      version: 1,
      timezone_name: "Europe/Moscow",
      completion_type: "standard.success",
      client_charge_type: "none",
      client_charge_value: 0,
      teacher_compensation_type: "fixed",
      teacher_compensation_value: 1000,
      subscription_id: null,
      trial: false,
      occurrence_count: 12,
      client_refs: [{ type: "lead", id: "lead-a" }],
    };
    const query = jest.fn(async (sqlValue: unknown, values?: unknown[]) => {
      const sql = String(sqlValue);
      if (sql.includes("pg_advisory_xact_lock")) {
        events.push(`lock:${String(values?.[0])}`);
        return { rows: [] };
      }
      if (sql.includes("for update")) {
        events.push("series-row");
        return { rows: [snapshot] };
      }
      if (
        sql.includes("from app.schedule_series") &&
        sql.includes("client_refs")
      ) {
        events.push("pre-read");
        return { rows: [snapshot] };
      }
      if (sql.includes("jsonb_to_recordset")) {
        events.push("active-client-recheck");
        return { rows: [] };
      }
      if (sql.includes("insert into app.schedule_series")) {
        events.push("write");
        continuationValues = values;
        return { rows: [{ id: "series-b" }] };
      }
      return { rows: [], rowCount: 1 };
    });
    const database = {
      transaction: (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    } as unknown as DatabaseService;
    const materializeSeries = jest.fn().mockResolvedValue(0);
    const service = new ScheduleSeriesService(
      database,
      { record: jest.fn() } as unknown as AuditService,
      { assertCanWriteCrm: jest.fn() } as unknown as CrmPolicy,
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
      { materializeSeries } as unknown as ScheduleSeriesMaterializerService,
    );

    await expect(
      service.updateScheduleSeries(actor, "series-a", {
        teacherId: "teacher-b",
        roomId: "room-b",
        effectiveFrom: "2026-08-01",
      }),
    ).resolves.toMatchObject({ id: "series-b" });

    expect(events).toEqual([
      "lock:commerce:multi-lesson-settlement",
      "pre-read",
      "lock:branch:branch-a",
      "lock:client:lead:lead-a",
      "lock:room:room-a",
      "lock:room:room-b",
      "lock:teacher:teacher-a",
      "lock:teacher:teacher-b",
      "lock:series:series-a",
      "series-row",
      "active-client-recheck",
      "write",
    ]);
    expect(continuationValues?.slice(0, 4)).toEqual([
      "lead",
      "lead-a",
      null,
      null,
    ]);
    expect(continuationValues?.slice(13, 22)).toEqual([
      "Europe/Moscow",
      "standard.success",
      "none",
      0,
      "fixed",
      1000,
      null,
      false,
      12,
    ]);
    expect(materializeSeries).toHaveBeenCalledWith(
      "series-b",
      expect.anything(),
      {
        outerLockContract: {
          prelockedKeys: [
            "branch:branch-a",
            "client:lead:lead-a",
            "room:room-a",
            "room:room-b",
            "teacher:teacher-a",
            "teacher:teacher-b",
          ],
          expectedKeys: [
            "branch:branch-a",
            "client:lead:lead-a",
            "room:room-b",
            "teacher:teacher-b",
          ],
        },
      },
    );
  });

  it("returns a typed stale conflict when the legacy pre-read changes before the row lock", async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date("2026-07-18T09:00:00.000Z"));
    const writes: string[] = [];
    const before = {
      id: "series-a",
      plan_id: null,
      client_type: null,
      client_id: null,
      student_id: "student-a",
      group_id: null,
      teacher_id: "teacher-a",
      room_id: "room-a",
      branch_id: "branch-a",
      weekday: 2,
      begin_time: "15:00:00",
      duration_minutes: 60,
      valid_from: "2026-07-15",
      valid_until: null,
      notes: null,
      superseded_by: null,
      deleted_at: null,
      version: 1,
      client_refs: [{ type: "student", id: "student-a" }],
    };
    const after = { ...before, teacher_id: "teacher-other", version: 2 };
    const query = jest.fn(async (sqlValue: unknown) => {
      const sql = String(sqlValue);
      if (sql.includes("pg_advisory_xact_lock")) return { rows: [] };
      if (sql.includes("for update")) return { rows: [after] };
      if (
        sql.includes("from app.schedule_series") &&
        sql.includes("client_refs")
      ) {
        return { rows: [before] };
      }
      if (/\b(update|insert|delete)\b/i.test(sql)) writes.push(sql);
      if (sql.includes("insert into app.schedule_series")) {
        return { rows: [{ id: "series-b" }] };
      }
      return { rows: [], rowCount: 1 };
    });
    const database = {
      transaction: (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    } as unknown as DatabaseService;
    const service = new ScheduleSeriesService(
      database,
      { record: jest.fn() } as unknown as AuditService,
      { assertCanWriteCrm: jest.fn() } as unknown as CrmPolicy,
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
      {
        materializeSeries: jest.fn().mockResolvedValue(0),
      } as unknown as ScheduleSeriesMaterializerService,
    );

    await expect(
      service.updateScheduleSeries(actor, "series-a", {
        effectiveFrom: "2026-08-01",
      }),
    ).rejects.toMatchObject({
      status: 409,
      response: { code: "SCHEDULE_SERIES_VERSION_STALE" },
    });
    expect(writes).toEqual([]);
  });

  it("serializes series edits and rejects a second continuation", async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date("2026-07-18T09:00:00.000Z"));
    const { series, query } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "series-a",
            student_id: "student-a",
            group_id: null,
            teacher_id: "teacher-a",
            room_id: "room-a",
            branch_id: "branch-a",
            weekday: 2,
            begin_time: "15:00:00",
            duration_minutes: 60,
            valid_from: "2026-07-15",
            valid_until: "2026-07-31",
            superseded_by: "series-b",
            notes: null,
            created_at: "2026-07-10",
            updated_at: "2026-07-18",
          },
        ],
      },
    ]);

    await expect(
      series.updateScheduleSeries(actor, "series-a", {
        effectiveFrom: "2026-08-01",
      }),
    ).rejects.toBeInstanceOf(ConflictException);

    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("insert into app.schedule_series"),
      ),
    ).toBe(false);
  });
});
