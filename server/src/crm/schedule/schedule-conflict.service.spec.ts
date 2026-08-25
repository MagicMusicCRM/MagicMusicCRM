import { BadRequestException, ConflictException } from "@nestjs/common";
import { DatabaseService } from "../../db/database.service";
import { CrmPolicy } from "../crm.policy";
import { ScheduleConflictService } from "./schedule-conflict.service";

describe("ScheduleConflictService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const busyRow = {
    lesson_id: "lesson-busy",
    title: "Анна Иванова",
    starts_at: "2026-07-20T10:00:00.000Z",
    ends_at: "2026-07-20T11:00:00.000Z",
    room_name: "101",
    teacher_name: "Иван Петров",
    teacher_hit: true,
    room_hit: false,
  };

  function createService(rows: Record<string, unknown>[] = []) {
    const query = jest.fn().mockImplementation((sql: unknown) =>
      Promise.resolve({
        rows: String(sql).includes("pg_advisory_xact_lock") ? [] : rows,
      }),
    );
    const policy = { assertManagerOnly: jest.fn() };
    const service = new ScheduleConflictService(
      { query } as unknown as DatabaseService,
      policy as unknown as CrmPolicy,
    );
    return { policy, query, service };
  }

  it("owns the manager preflight response contract", async () => {
    const { policy, query, service } = createService([busyRow]);

    await expect(
      service.getScheduleConflicts(actor, {
        teacherId: "teacher-a",
        startsAt: "2026-07-20T10:30:00.000Z",
        endsAt: "2026-07-20T11:30:00.000Z",
      }),
    ).resolves.toMatchObject({
      teacherBusy: true,
      roomBusy: false,
      conflicts: [{ lessonId: "lesson-busy" }],
    });

    expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[0]?.[0]);
    expect(sql).toContain(
      "l.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')",
    );
    expect(sql).toContain("l.deleted_at is null");
    expect(sql).toContain("tstzrange");
    expect(sql).toContain("l.group_id <> $6");
  });

  it("reports a free slot without querying when no resource is selected", async () => {
    const { query, service } = createService();

    await expect(
      service.getScheduleConflicts(actor, {
        startsAt: "2026-07-20T10:30:00.000Z",
        endsAt: "2026-07-20T11:30:00.000Z",
      }),
    ).resolves.toEqual({
      teacherBusy: false,
      roomBusy: false,
      conflicts: [],
    });
    expect(query).not.toHaveBeenCalled();
  });

  it("rejects a reversed range before querying", async () => {
    const { query, service } = createService();

    await expect(
      service.getScheduleConflicts(actor, {
        teacherId: "teacher-a",
        startsAt: "2026-07-20T11:30:00.000Z",
        endsAt: "2026-07-20T10:30:00.000Z",
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(query).not.toHaveBeenCalled();
  });

  it("uses the supplied executor for the atomic lock and conflict query", async () => {
    const { service } = createService();
    const query = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [busyRow] });

    const promise = service.assertNoScheduleConflicts(
      {
        teacherId: "teacher-a",
        roomId: null,
        startsAt: "2026-07-20T10:30:00.000Z",
        durationMinutes: 60,
      },
      { query },
    );

    await expect(promise).rejects.toBeInstanceOf(ConflictException);
    expect(query).toHaveBeenCalledTimes(2);
    expect(String(query.mock.calls[0]?.[0])).toContain(
      "pg_advisory_xact_lock",
    );
    expect(String(query.mock.calls[1]?.[0])).toContain("tstzrange");
  });
});
