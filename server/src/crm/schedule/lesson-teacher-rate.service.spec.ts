import { ForbiddenException } from "@nestjs/common";
import { AuditService } from "../../audit/audit.service";
import { DatabaseService } from "../../db/database.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { CrmPolicy } from "../crm.policy";
import { LessonTeacherRateService } from "./lesson-teacher-rate.service";

describe("LessonTeacherRateService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };
  const metadata = {
    idempotencyKey: "bulk-rate-test-001",
    requestId: "bulk-rate-request-001",
  };

  const buildDeps = (policyOverride?: CrmPolicy) => ({
    audit: { record: jest.fn().mockResolvedValue(undefined) },
    policy: policyOverride ?? { assertCanManagePayrollHistory: jest.fn() },
  });

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
    policyOverride?: CrmPolicy,
  ) => {
    const queuedResults = [...results];
    const query = jest
      .fn()
      .mockImplementation(() => Promise.resolve(queuedResults.shift()));
    const deps = buildDeps(policyOverride);
    const database = {
      query,
      transaction: (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    } as unknown as DatabaseService;
    const platform = {
      executeVersionedMutation: jest.fn(async ({ mutate }) => ({
        resultRef: await mutate({ query } as never, 1),
        version: 1,
        replayed: false,
      })),
    } as unknown as PlatformIntegrityService;
    const service = new LessonTeacherRateService(
      deps.policy as unknown as CrmPolicy,
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
      platform,
    );
    return { service, query, platform, ...deps };
  };

  describe("bulk teacher rate", () => {
    it.each([
      ["client", false],
      ["teacher", false],
      ["admin", false],
      ["manager", false],
      ["director", true],
      ["system_admin", true],
    ] as const)(
      "allows bulk lesson-rate mutation only for owner role %s",
      async (role, allowed) => {
        const { service, query } = createServiceWithQueryResults(
          [
            { rows: [{ id: "lesson-a", locked: false }] },
            { rows: [{ id: "lesson-a" }] },
          ],
          new CrmPolicy(),
        );
        const mutation = service.setLessonsTeacherRate(
          { userId: `${role}-a`, role },
          {
            lessonIds: ["lesson-a"],
            teacherRate: 900,
            reasonText: "Плановое изменение ставки",
            expectedVersion: 0,
          },
          metadata,
        );

        if (allowed) {
          await expect(mutation).resolves.toMatchObject({ updated: 1 });
          expect(query).toHaveBeenCalledTimes(2);
        } else {
          await expect(mutation).rejects.toBeInstanceOf(ForbiddenException);
          expect(query).not.toHaveBeenCalled();
        }
      },
    );

    it("reprices every lesson in one statement and reports the count", async () => {
      const { service, query, platform } = createServiceWithQueryResults([
        {
          rows: [
            { id: "lesson-a", locked: false },
            { id: "lesson-b", locked: false },
          ],
        },
        { rows: [{ id: "lesson-a" }, { id: "lesson-b" }] },
      ]);

      await expect(
        service.setLessonsTeacherRate(
          actor,
          {
            lessonIds: ["lesson-a", "lesson-b"],
            teacherRate: 0,
            reasonText: "Исправление ставки",
            expectedVersion: 0,
          },
          metadata,
        ),
      ).resolves.toEqual({
        updated: 2,
        correctedSettled: 0,
        lessonIds: ["lesson-a", "lesson-b"],
      });

      // One locked validation plus one atomic update, not one PATCH per lesson.
      expect(query).toHaveBeenCalledTimes(2);
      expect(query.mock.calls[1][1]).toEqual([["lesson-a", "lesson-b"], 0]);
      expect(platform.executeVersionedMutation).toHaveBeenCalledWith(
        expect.objectContaining({
          expectedVersion: 0,
          audit: expect.objectContaining({
            action: "crm.lessons_teacher_rate_bulk_set",
          }),
          outbox: expect.objectContaining({
            type: "crm.lesson_teacher_rate.changed",
          }),
        }),
      );
    });

    it("replays the stored batch result without a duplicate compensation fact", async () => {
      const { service, query, platform } = createServiceWithQueryResults([]);
      (platform.executeVersionedMutation as jest.Mock).mockResolvedValueOnce({
        resultRef: { lessonIds: ["lesson-a"], correctedSettled: 1 },
        version: 4,
        replayed: true,
      });

      await expect(
        service.setLessonsTeacherRate(
          { userId: "director-a", role: "director" },
          {
            lessonIds: ["lesson-a"],
            teacherRate: 900,
            reasonText: "Повтор запроса после сетевой ошибки",
            expectedVersion: 3,
          },
          metadata,
        ),
      ).resolves.toEqual({
        updated: 1,
        correctedSettled: 1,
        lessonIds: ["lesson-a"],
      });
      expect(query).not.toHaveBeenCalled();
    });

    it("keeps a rate of 0 rather than treating it as 'no rate given'", async () => {
      const { service, query } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: false }] },
        { rows: [{ id: "lesson-a" }] },
      ]);

      await service.setLessonsTeacherRate(
        actor,
        {
          lessonIds: ["lesson-a"],
          teacherRate: 0,
          reasonText: "Исправление ставки",
          expectedVersion: 0,
        },
        metadata,
      );

      // 0 is «входит в оклад» — the whole point of the bulk pass. A `|| null`
      // anywhere in this path would silently turn it into "clear the override".
      expect(query.mock.calls[1][1][1]).toBe(0);
    });

    it("clears the override when no rate is given", async () => {
      const { service, query } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: false }] },
        { rows: [{ id: "lesson-a" }] },
      ]);

      await service.setLessonsTeacherRate(
        actor,
        {
          lessonIds: ["lesson-a"],
          reasonText: "Вернуть наследуемую ставку",
          expectedVersion: 0,
        },
        metadata,
      );

      // Sets, not coalesces: falling back to the group/history rate has to be
      // expressible, and coalesce cannot express it.
      expect(String(query.mock.calls[1][0])).toContain(
        "teacher_rate = $2::numeric",
      );
      expect(query.mock.calls[1][1][1]).toBeNull();
    });

    it("requires owner-level payroll authorization", async () => {
      const { service, policy } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: false }] },
        { rows: [{ id: "lesson-a" }] },
      ]);

      await service.setLessonsTeacherRate(
        actor,
        {
          lessonIds: ["lesson-a"],
          reasonText: "Исправление ставки",
          expectedVersion: 0,
        },
        metadata,
      );

      expect(policy.assertCanManagePayrollHistory).toHaveBeenCalledWith(actor);
    });

    it("rejects immutable settled lessons before changing any rate", async () => {
      const { service, query, audit } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: true }] },
      ]);

      await expect(
        service.setLessonsTeacherRate(
          actor,
          {
            lessonIds: ["lesson-a"],
            teacherRate: 0,
            reasonText: "Исправление ставки",
            expectedVersion: 0,
          },
          metadata,
        ),
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
      const { service, query, platform } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: true }] },
        { rows: [{ id: "lesson-a" }] },
        { rows: [] },
      ]);

      await expect(
        service.setLessonsTeacherRate(
          director,
          {
            lessonIds: ["lesson-a"],
            teacherRate: 900,
            reasonText: "Исправление ошибочной ставки администратора",
            expectedVersion: 0,
          },
          metadata,
        ),
      ).resolves.toEqual({
        updated: 1,
        correctedSettled: 1,
        lessonIds: ["lesson-a"],
      });

      expect(String(query.mock.calls[2][0])).toContain("supersedes_fact_id");
      expect(platform.executeVersionedMutation).toHaveBeenCalledTimes(1);
    });
  });
});
