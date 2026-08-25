import { AuditService } from "../../audit/audit.service";
import { DatabaseService } from "../../db/database.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { LessonTeacherRateService } from "./lesson-teacher-rate.service";

describe("LessonTeacherRateService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const buildDeps = () => ({
    audit: { record: jest.fn().mockResolvedValue(undefined) },
    policy: { assertManagerOnly: jest.fn() },
  });

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const queuedResults = [...results];
    const query = jest.fn().mockImplementation(() =>
      Promise.resolve(queuedResults.shift()),
    );
    const deps = buildDeps();
    const database = {
      query,
      transaction: (
        work: (client: { query: jest.Mock }) => Promise<unknown>,
      ) => work({ query }),
    } as unknown as DatabaseService;
    const service = new LessonTeacherRateService(
      database,
      deps.audit as unknown as AuditService,
      deps.policy as unknown as CrmPolicy,
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
    );
    return { service, query, ...deps };
  };

describe("bulk teacher rate", () => {
    it("reprices every lesson in one statement and reports the count", async () => {
      const { service, query, audit } = createServiceWithQueryResults([
        {
          rows: [
            { id: "lesson-a", locked: false },
            { id: "lesson-b", locked: false },
          ],
        },
        { rows: [{ id: "lesson-a" }, { id: "lesson-b" }] },
      ]);

      await expect(
        service.setLessonsTeacherRate(actor, {
          lessonIds: ["lesson-a", "lesson-b"],
          teacherRate: 0,
          reasonText: "Исправление ставки",
        }),
      ).resolves.toEqual({
        updated: 2,
        correctedSettled: 0,
        lessonIds: ["lesson-a", "lesson-b"],
      });

      // One locked validation plus one atomic update, not one PATCH per lesson.
      expect(query).toHaveBeenCalledTimes(2);
      expect(query.mock.calls[1][1]).toEqual([["lesson-a", "lesson-b"], 0]);
      expect(audit.record).toHaveBeenCalledWith(
        expect.objectContaining({
          action: "crm.lessons_teacher_rate_bulk_set",
          metadata: expect.objectContaining({ teacherRate: 0, updated: 2 }),
        }),
      );
    });

    it("keeps a rate of 0 rather than treating it as 'no rate given'", async () => {
      const { service, query } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: false }] },
        { rows: [{ id: "lesson-a" }] },
      ]);

      await service.setLessonsTeacherRate(actor, {
        lessonIds: ["lesson-a"],
        teacherRate: 0,
        reasonText: "Исправление ставки",
      });

      // 0 is «входит в оклад» — the whole point of the bulk pass. A `|| null`
      // anywhere in this path would silently turn it into "clear the override".
      expect(query.mock.calls[1][1][1]).toBe(0);
    });

    it("clears the override when no rate is given", async () => {
      const { service, query } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: false }] },
        { rows: [{ id: "lesson-a" }] },
      ]);

      await service.setLessonsTeacherRate(actor, {
        lessonIds: ["lesson-a"],
        reasonText: "Вернуть наследуемую ставку",
      });

      // Sets, not coalesces: falling back to the group/history rate has to be
      // expressible, and coalesce cannot express it.
      expect(String(query.mock.calls[1][0])).toContain(
        "teacher_rate = $2::numeric",
      );
      expect(query.mock.calls[1][1][1]).toBeNull();
    });

    it("is manager-only — it writes payroll inputs across the schedule", async () => {
      const { service, policy } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: false }] },
        { rows: [{ id: "lesson-a" }] },
      ]);

      await service.setLessonsTeacherRate(actor, {
        lessonIds: ["lesson-a"],
        reasonText: "Исправление ставки",
      });

      expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    });

    it("rejects immutable settled lessons before changing any rate", async () => {
      const { service, query, audit } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: true }] },
      ]);

      await expect(
        service.setLessonsTeacherRate(actor, {
          lessonIds: ["lesson-a"],
          teacherRate: 0,
          reasonText: "Исправление ставки",
        }),
      ).rejects.toMatchObject({
        response: expect.objectContaining({
          code: "SETTLED_TEACHER_RATE_IMMUTABLE",
          canonicalAction: "lesson_settlement_correction",
        }),
      });

      expect(query).toHaveBeenCalledTimes(1);
      expect(String(query.mock.calls[0][0])).not.toContain(
        "update app.lessons",
      );
      expect(audit.record).not.toHaveBeenCalled();
    });

    it("lets a director correct settled rates with a superseding fact", async () => {
      const director = { userId: "director-a", role: "director" as const };
      const { service, query, audit } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: true }] },
        { rows: [{ id: "lesson-a" }] },
        { rows: [] },
      ]);

      await expect(
        service.setLessonsTeacherRate(director, {
          lessonIds: ["lesson-a"],
          teacherRate: 900,
          reasonText: "Исправление ошибочной ставки администратора",
        }),
      ).resolves.toEqual({
        updated: 1,
        correctedSettled: 1,
        lessonIds: ["lesson-a"],
      });

      expect(String(query.mock.calls[2][0])).toContain(
        "supersedes_fact_id",
      );
      expect(audit.record).toHaveBeenCalledWith(
        expect.objectContaining({
          metadata: expect.objectContaining({
            correctedSettled: 1,
            reason: "Исправление ошибочной ставки администратора",
          }),
        }),
      );
    });
  });
});

