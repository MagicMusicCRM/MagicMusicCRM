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
      transaction: (
        work: (client: { query: jest.Mock }) => Promise<unknown>,
      ) => work({ query }),
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
    const query = jest.fn().mockImplementation((sql: unknown) => {
      if (String(sql).includes("pg_advisory_xact_lock")) {
        return Promise.resolve({ rows: [] });
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
+it("creates a schedule series and materializes lessons up to the horizon (KVA-236)", async () => {
    const { series, query, audit } = createServiceWithQueryResults([
      { rows: [{ id: "series-a" }] }, // insert series
      {
        rows: [
          {
            series_date: "2026-07-21",
            plan_id: null,
            group_id: null,
            teacher_id: "teacher-a",
            branch_id: "branch-a",
            room_id: "room-a",
            starts_at: "2026-07-21T12:00:00.000Z",
            ends_at: "2026-07-21T13:00:00.000Z",
            client_refs: [{ type: "student", id: "student-a" }],
          },
        ],
      }, // candidates before locks
      {
        rows: [
          {
            series_date: "2026-07-21",
            plan_id: null,
            group_id: null,
            teacher_id: "teacher-a",
            branch_id: "branch-a",
            room_id: "room-a",
            starts_at: "2026-07-21T12:00:00.000Z",
            ends_at: "2026-07-21T13:00:00.000Z",
            client_refs: [{ type: "student", id: "student-a" }],
          },
        ],
      }, // candidates after locks
      { rows: [] }, // materialize insert..select
    ]);

    await expect(
      series.createScheduleSeries(actor, {
        studentId: "student-a",
        teacherId: "teacher-a",
        branchId: "branch-a",
        roomId: "room-a",
        weekday: 2,
        beginTime: "15:00",
        durationMinutes: 60,
        validFrom: "2026-07-15",
        // validUntil отсутствует — «до бесконечности»
      }),
    ).resolves.toEqual({ id: "series-a", lessonsCreated: 0 });

    const materializeCall = query.mock.calls.find((call) =>
      String(call[0]).includes("insert into app.lessons"),
    );
    const materializeSql = String(materializeCall?.[0]);
    expect(materializeSql).toContain("generate_series");
    expect(materializeSql).toContain("extract(isodow from d) = s.weekday");
    // Идемпотентность: занятая series_date (вкл. перенесённые/отменённые) не пересоздаётся.
    expect(materializeSql).toContain(
      "l.series_id = s.id and l.series_date = d::date",
    );
    expect(materializeSql).toContain(
      "on conflict (series_id, series_date) where deleted_at is null",
    );
    expect(materializeCall?.[1]).toEqual(["series-a", 60, 400]);
    expect(
      query.mock.calls.some(
        (call) =>
          String(call[0]).includes("pg_advisory_xact_lock") &&
          call[1][0] === "series:series-a",
      ),
    ).toBe(true);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.schedule_series_created" }),
    );
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
      "manager-a",
    ]);
    expect(
      query.mock.calls.some((call) => String(call[0]).includes("for update")),
    ).toBe(true);
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
    expect(sql).not.toContain("series_date >= $2::date");
    expect(sql).not.toContain("original_scheduled_at is null");
    expect(lessonUpdate?.[1]).toEqual(["series-a", "2026-12-01"]);
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

it("rejects an ambiguous recurring-series subject", async () => {
      const { series, query } = createServiceWithQueryResults([]);
      await expect(
        series.createScheduleSeries(actor, {
          studentId: "student-a",
          groupId: "group-a",
          weekday: 1,
          beginTime: "10:00",
          validFrom: "2026-07-21",
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(query).not.toHaveBeenCalled();
    });

it("runs the recurring conflict guard before materializing a series", async () => {
      const { series, query, constraints } = createServiceWithQueryResults([
        { rows: [{ id: "series-a" }] },
        {
          rows: [
            {
              series_date: "2026-07-21",
              plan_id: null,
              group_id: null,
              teacher_id: "teacher-a",
              branch_id: "branch-a",
              room_id: "room-a",
              starts_at: "2026-07-21T10:00:00.000Z",
              ends_at: "2026-07-21T11:00:00.000Z",
              client_refs: [{ type: "student", id: "student-a" }],
            },
          ],
        },
        {
          rows: [
            {
              series_date: "2026-07-21",
              plan_id: null,
              group_id: null,
              teacher_id: "teacher-a",
              branch_id: "branch-a",
              room_id: "room-a",
              starts_at: "2026-07-21T10:00:00.000Z",
              ends_at: "2026-07-21T11:00:00.000Z",
              client_refs: [{ type: "student", id: "student-a" }],
            },
          ],
        },
      ]);
      constraints.validate.mockResolvedValue({
        valid: false,
        violations: [
          {
            code: "TEACHER_OVERLAP",
            resource: { type: "teacher", id: "teacher-a" },
            conflictingLessonIds: ["busy-a"],
            ruleIds: [],
          },
        ],
      });

      await expect(
        series.createScheduleSeries(actor, {
          studentId: "student-a",
          teacherId: "teacher-a",
          branchId: "branch-a",
          roomId: "room-a",
          weekday: 1,
          beginTime: "10:00",
          validFrom: "2026-07-21",
        }),
      ).rejects.toMatchObject({
        response: expect.objectContaining({
          code: "LESSON_SERIES_CONSTRAINT_VIOLATIONS",
        }),
      });

      const conflictCall = query.mock.calls.find((call) =>
        String(call[0]).includes("with target as"),
      );
      expect(conflictCall).toBeDefined();
      expect(
        query.mock.calls.some((call) =>
          String(call[0]).includes("insert into app.lessons"),
        ),
      ).toBe(false);
    });
});
