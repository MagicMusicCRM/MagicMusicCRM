import { HttpException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { ClientReferenceService } from "../clients/client-reference.service";
import { CrmPolicy } from "../crm.policy";
import { AvailabilityRepository } from "./availability.repository";
import { ConstraintEngineRepository } from "./constraint-engine.repository";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import { LessonCommandRepository } from "./lesson-command.repository";
import { LessonCommandService } from "./lesson-command.service";
import { LessonConstraintPreviewService } from "./lesson-constraint-preview.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonPlannedSettlementCommandService } from "./lesson-planned-settlement-command.service";
import { LessonRequiredFieldValidator } from "./lesson-required-field.validator";
import { LessonWriteCommandService } from "./lesson-write-command.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { UpsertLessonDto } from "../dto/upsert-lesson.dto";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(testDatabaseUrl).hostname,
  )
) {
  throw new Error("Lesson write parity tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Unified lesson create and protected transition writes (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let commands: LessonCommandService;

  beforeAll(async () => {
    pool = new Pool({ connectionString: testDatabaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    const availability = new AvailabilityRepository(database);
    const platform = new PlatformIntegrityService(
      database,
      new PlatformIntegrityRepository(),
    );
    const policy = new CrmPolicy();
    const constraints = new ScheduleConstraintEngine(
      new ConstraintEngineRepository(database, availability),
    );
    const reservations = new SubscriptionReservationService(database, {
      emitCrmChanged: jest.fn(),
      emitFinanceChanged: jest.fn(),
    } as unknown as RealtimeBus);
    const settlement = new LessonSettlementService(database);
    const previewTokens = new SubscriptionPreviewTokenService({
      get: (key: string) =>
        key === "COMMERCE_PREVIEW_SECRET"
          ? "lesson-write-parity-preview-secret-32-bytes"
          : "",
    } as unknown as ConfigService);
    const repository = new LessonCommandRepository(database);
    commands = new LessonCommandService(
      new LessonConstraintPreviewService(policy, constraints),
      new LessonWriteCommandService(
        platform,
        policy,
        new ClientReferenceService(database),
        new LessonRequiredFieldValidator(),
        constraints,
        new LessonLifecycleRepository(database),
        reservations,
        settlement,
        repository,
      ),
      new LessonPlannedSettlementCommandService(
        database,
        platform,
        policy,
        reservations,
        settlement,
        previewTokens,
        repository,
      ),
    );
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await pool.end();
  });

  it("keeps create constraint parity and rejects direct edit/drag bypasses", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const keys: string[] = [];
    const key = (name: string) => {
      const value = `lesson-${name}-${randomUUID()}`;
      keys.push(value);
      return {
        idempotencyKey: value,
        requestId: `request-${name}-${randomUUID()}`,
      };
    };
    const base = {
      clientRef: { type: "student" as const, id: fixture.studentId },
      teacherId: fixture.teacherId,
      branchId: fixture.branchId,
      roomId: fixture.roomId,
      durationMinutes: 60,
      isTrial: false,
      completionType: "standard.success",
      clientChargeType: "none" as const,
      clientChargeValue: 0,
      teacherCompensationType: "fixed" as const,
      teacherCompensationValue: 700,
      financialDecision: {
        settlementTypeKey: "free_lesson",
        teacherCompensationRuleKey: "none",
      },
    };
    const createdIds: string[] = [];
    try {
      const seed = await commands.create(
        actor,
        { ...base, scheduledAt: "2026-07-27T07:00:00.000Z" },
        key("seed"),
      );
      createdIds.push(seed.id);
      const editable = await commands.create(
        actor,
        { ...base, scheduledAt: "2026-07-27T09:00:00.000Z" },
        key("editable"),
      );
      createdIds.push(editable.id);

      const invalidCreate = await violationResponse(() =>
        commands.create(
          actor,
          { ...base, scheduledAt: "2026-07-27T07:30:00.000Z" },
          key("invalid-create"),
        ),
      );
      const preview = await commands.previewConstraints(actor, {
        clientRef: base.clientRef,
        teacherId: base.teacherId,
        branchId: base.branchId,
        roomId: base.roomId,
        scheduledAt: "2026-07-27T07:30:00.000Z",
        durationMinutes: base.durationMinutes,
      });
      const invalidEdit = await violationResponse(() =>
        commands.update(
          actor,
          editable.id,
          {
            ...base,
            expectedVersion: editable.version,
            scheduledAt: "2026-07-27T07:30:00.000Z",
          },
          key("invalid-edit"),
        ),
      );
      const invalidDrag = await violationResponse(() =>
        commands.update(
          actor,
          editable.id,
          {
            expectedVersion: editable.version,
            scheduledAt: "2026-07-27T07:30:00.000Z",
          },
          key("invalid-drag"),
        ),
      );
      expect(preview.violations).toEqual(invalidCreate.violations);
      expect(invalidEdit).toEqual({
        code: "LESSON_TRANSITION_REQUIRED",
        violations: undefined,
      });
      expect(invalidDrag).toEqual(invalidEdit);
      expect(invalidCreate).toEqual({
        code: "LESSON_CONSTRAINT_VIOLATIONS",
        violations: [
          {
            code: "TEACHER_OVERLAP",
            resource: { type: "teacher", id: fixture.teacherId },
            conflictingLessonIds: [seed.id],
            ruleIds: [],
          },
          {
            code: "CLIENT_OVERLAP",
            resource: { type: "client", id: fixture.studentId },
            conflictingLessonIds: [seed.id],
            ruleIds: [],
          },
          {
            code: "ROOM_OVERLAP",
            resource: { type: "room", id: fixture.roomId },
            conflictingLessonIds: [seed.id],
            ruleIds: [],
          },
        ],
      });

      const createMetadata = key("replay");
      const replayDto = {
        ...base,
        scheduledAt: "2026-07-27T10:00:00.000Z",
      };
      const first = await commands.create(actor, replayDto, createMetadata);
      const replay = await commands.create(actor, replayDto, createMetadata);
      createdIds.push(first.id);
      expect(replay).toMatchObject({
        id: first.id,
        version: first.version,
        replayed: true,
      });
      const count = await pool.query<{ count: string }>(
        "select count(*)::text as count from app.lessons where id = $1",
        [first.id],
      );
      expect(count.rows[0]!.count).toBe("1");

      await expect(
        commands.update(
          actor,
          editable.id,
          {
            expectedVersion: editable.version,
            scheduledAt: "2026-07-27T11:00:00.000Z",
          },
          key("valid-drag"),
        ),
      ).rejects.toMatchObject({ status: 422 });
    } finally {
      await cleanupFixture(pool, {
        ...fixture,
        actorKey: `user:${fixture.managerId}`,
        lessonIds: createdIds,
      });
    }
  });

  it("requires independent settlement, pay rule and funding source before atomic create", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const directorUser = await pool.query<{ id: string }>(
      `insert into app.users (email, role, email_verified_at)
       values ($1, 'director', now())
       returning id`,
      [`parity-director-${randomUUID()}@example.test`],
    );
    const director = {
      userId: directorUser.rows[0]!.id,
      role: "director" as const,
    };
    const lessonIds: string[] = [];
    const metadata = (name: string) => ({
      idempotencyKey: `lesson-required-financial-${name}-${randomUUID()}`,
      requestId: `lesson-required-financial-request-${name}-${randomUUID()}`,
    });
    const complete: UpsertLessonDto = {
      clientRef: { type: "student", id: fixture.studentId },
      teacherId: fixture.teacherId,
      branchId: fixture.branchId,
      roomId: fixture.roomId,
      scheduledAt: nextMondayAtTenMoscow(),
      durationMinutes: 60,
      isTrial: false,
      completionType: "standard.success",
      clientChargeType: "personal_account",
      clientChargeValue: 1500,
      teacherCompensationType: "none",
      teacherCompensationValue: 0,
      financialDecision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "none",
      },
    };
    try {
      await expectCommandError(
        () =>
          commands.create(
            actor,
            { ...complete, clientChargeType: undefined },
            metadata("missing-source"),
          ),
        {
          code: "LESSON_REQUIRED_FIELDS",
          fields: ["clientChargeType"],
        },
      );
      await expectCommandError(
        () =>
          commands.create(
            actor,
            { ...complete, financialDecision: undefined },
            metadata("missing-decision"),
          ),
        {
          code: "LESSON_SETTLEMENT_PLAN_REQUIRED",
          fields: ["financialDecision"],
        },
      );
      await expectCommandError(
        () =>
          commands.create(
            director,
            {
              ...complete,
              financialDecision: {
                teacherCompensationRuleKey: "none",
              },
            } as UpsertLessonDto,
            metadata("missing-settlement"),
          ),
        {
          code: "SETTLEMENT_TYPE_NOT_ALLOWED",
          field: "settlementTypeKey",
        },
      );
      await expectCommandError(
        () =>
          commands.create(
            director,
            {
              ...complete,
              financialDecision: { settlementTypeKey: "lesson" },
            } as UpsertLessonDto,
            metadata("missing-pay-rule"),
          ),
        {
          code: "TEACHER_COMPENSATION_RULE_NOT_FOUND",
          field: "teacherCompensationRuleKey",
        },
      );
      await expectCommandError(
        () =>
          commands.create(
            actor,
            {
              ...complete,
              clientChargeType: "subscription",
              subscriptionId: undefined,
            },
            metadata("subscription-without-id"),
          ),
        {
          code: "INVALID_FINANCIAL_SNAPSHOT",
          fields: ["clientChargeType", "subscriptionId"],
        },
      );
      await expectCommandError(
        () =>
          commands.create(
            actor,
            {
              ...complete,
              clientChargeType: "none",
              clientChargeValue: 0,
            },
            metadata("paid-without-source"),
          ),
        { code: "CLIENT_FUNDING_SOURCE_REQUIRED" },
      );

      const before = await pool.query<{ lessons: string; plans: string }>(
        `select
           (select count(*)::text from app.lessons where created_by = $1)
             as lessons,
           (select count(*)::text from app.lesson_settlement_plans plan
              join app.lessons lesson on lesson.id = plan.lesson_id
              where lesson.created_by = $1) as plans`,
        [fixture.managerId],
      );
      expect(before.rows[0]).toEqual({ lessons: "0", plans: "0" });

      const created = await commands.create(
        actor,
        complete,
        metadata("valid-personal-account"),
      );
      lessonIds.push(created.id);
      const persisted = await pool.query<{
        charge_type: string;
        charge_value: string;
        subscription_id: string | null;
        settlement_key: string;
        pay_rule_key: string;
        plan_revisions: string;
        reservations: string;
      }>(
        `select snapshot.client_charge_type as charge_type,
           snapshot.client_charge_value::text as charge_value,
           snapshot.subscription_id,
           plan.decision ->> 'settlementTypeKey' as settlement_key,
           plan.decision ->> 'teacherCompensationRuleKey' as pay_rule_key,
           (select count(*)::text
              from app.lesson_settlement_plan_revisions revision
              where revision.lesson_id = lesson.id) as plan_revisions,
           (select count(*)::text from app.lesson_reservations reservation
              where reservation.lesson_id = lesson.id) as reservations
         from app.lessons lesson
         join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
         join app.lesson_settlement_plans plan on plan.lesson_id = lesson.id
         where lesson.id = $1`,
        [created.id],
      );
      expect(persisted.rows[0]).toEqual({
        charge_type: "personal_account",
        charge_value: "1500.00",
        subscription_id: null,
        settlement_key: "lesson",
        pay_rule_key: "standard",
        plan_revisions: "1",
        reservations: "0",
      });
    } finally {
      await cleanupFixture(pool, {
        ...fixture,
        actorKey: `user:${fixture.managerId}`,
        extraActorKeys: [`user:${director.userId}`],
        extraActorUserIds: [director.userId],
        extraUserIds: [director.userId],
        lessonIds,
      });
    }
  });

  it("creates a Lead trial with required resources and an immutable calculation snapshot", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const lessonIds: string[] = [];
    const scheduledAt = nextMondayAtTenMoscow();
    const metadata = {
      idempotencyKey: `lead-trial-create-${randomUUID()}`,
      requestId: `lead-trial-request-${randomUUID()}`,
    };
    const draft: UpsertLessonDto = {
      clientRef: { type: "lead", id: fixture.leadId },
      teacherId: fixture.teacherId,
      branchId: fixture.branchId,
      roomId: fixture.roomId,
      scheduledAt,
      durationMinutes: 60,
      isTrial: true,
      completionType: "standard.success",
      clientChargeType: "none",
      clientChargeValue: 0,
      teacherCompensationType: "hourly",
      teacherCompensationValue: 1250,
      financialDecision: {
        settlementTypeKey: "free_lesson",
        teacherCompensationRuleKey: "standard",
      },
    };
    try {
      await pool.query(
        `insert into app.teacher_rates (
           teacher_id, rate, effective_from, created_by
         ) values ($1, 900, '2026-01-01', $2)`,
        [fixture.teacherId, fixture.managerId],
      );
      await expect(
        commands.previewConstraints(actor, {
          clientRef: draft.clientRef!,
          teacherId: draft.teacherId!,
          branchId: draft.branchId!,
          roomId: draft.roomId!,
          scheduledAt,
          durationMinutes: draft.durationMinutes!,
        }),
      ).resolves.toMatchObject({ valid: true, violations: [] });

      const created = await commands.create(actor, draft, metadata);
      lessonIds.push(created.id);
      expect(created).toMatchObject({
        clientRef: { type: "lead", id: fixture.leadId },
        leadId: fixture.leadId,
        teacherId: fixture.teacherId,
        branchId: fixture.branchId,
        roomId: fixture.roomId,
        isTrial: true,
      });

      const persisted = await pool.query<{
        lead_id: string;
        student_id: string | null;
        teacher_id: string;
        branch_id: string;
        room_id: string;
        is_trial: boolean;
        client_type: string;
        client_id: string;
        snapshot_trial: boolean;
        completion_type: string;
        charge_type: string;
        charge_value: string;
        compensation_type: string;
        compensation_value: string;
        validation_state: string;
        settlement_key: string;
        pay_rule_key: string;
        plan_revisions: string;
      }>(
        `select lesson.lead_id, lesson.student_id, lesson.teacher_id,
           lesson.branch_id, lesson.room_id, lesson.is_trial,
           snapshot.client_type, snapshot.client_id,
           snapshot.trial as snapshot_trial, snapshot.completion_type,
           snapshot.client_charge_type as charge_type,
           snapshot.client_charge_value::text as charge_value,
           snapshot.teacher_compensation_type as compensation_type,
           snapshot.teacher_compensation_value::text as compensation_value,
           snapshot.validation_state,
           plan.decision ->> 'settlementTypeKey' as settlement_key,
           plan.decision ->> 'teacherCompensationRuleKey' as pay_rule_key,
           (select count(*)::text
              from app.lesson_settlement_plan_revisions revision
              where revision.lesson_id = lesson.id) as plan_revisions
         from app.lessons lesson
         join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
         join app.lesson_settlement_plans plan on plan.lesson_id = lesson.id
         where lesson.id = $1`,
        [created.id],
      );
      expect(persisted.rows[0]).toEqual({
        lead_id: fixture.leadId,
        student_id: null,
        teacher_id: fixture.teacherId,
        branch_id: fixture.branchId,
        room_id: fixture.roomId,
        is_trial: true,
        client_type: "lead",
        client_id: fixture.leadId,
        snapshot_trial: true,
        completion_type: "standard.success",
        charge_type: "none",
        charge_value: "0.00",
        compensation_type: "hourly",
        compensation_value: "900.00",
        validation_state: "valid",
        settlement_key: "free_lesson",
        pay_rule_key: "standard",
        plan_revisions: "1",
      });
    } finally {
      await pool.query("delete from app.teacher_rates where teacher_id = $1", [
        fixture.teacherId,
      ]);
      await cleanupFixture(pool, {
        ...fixture,
        actorKey: `user:${fixture.managerId}`,
        lessonIds,
      });
    }
  });

  it("clears a null notes-only PATCH through the canonical command path", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const lessonIds: string[] = [];
    const metadata = (name: string) => ({
      idempotencyKey: `notes-only-${name}-${randomUUID()}`,
      requestId: `notes-only-request-${name}-${randomUUID()}`,
    });
    try {
      const lesson = await commands.create(
        actor,
        {
          clientRef: { type: "student", id: fixture.studentId },
          teacherId: fixture.teacherId,
          branchId: fixture.branchId,
          roomId: fixture.roomId,
          scheduledAt: "2026-07-27T07:00:00.000Z",
          durationMinutes: 60,
          isTrial: false,
          completionType: "standard.success",
          clientChargeType: "none",
          clientChargeValue: 0,
          teacherCompensationType: "fixed",
          teacherCompensationValue: 700,
          notes: "Старая заметка",
          financialDecision: {
            settlementTypeKey: "free_lesson",
            teacherCompensationRuleKey: "none",
          },
        },
        metadata("create"),
      );
      lessonIds.push(lesson.id);

      const patched = await commands.update(
        actor,
        lesson.id,
        {
          expectedVersion: lesson.version,
          notes: null as never,
        },
        metadata("clear"),
      );
      const persisted = await pool.query<{ notes: string | null }>(
        "select notes from app.lessons where id = $1",
        [lesson.id],
      );

      expect(patched.version).toBe(lesson.version + 1);
      expect(persisted.rows[0]!.notes).toBeNull();
    } finally {
      await cleanupFixture(pool, {
        ...fixture,
        actorKey: `user:${fixture.managerId}`,
        lessonIds,
      });
    }
  });

  it("keeps assigned operational staff inside their lesson branch for notes-only PATCHes", async () => {
    const assigned = await createFixture(pool);
    const assignedAdmin = await createFixture(pool, "admin");
    const foreign = await createFixture(pool);
    const assignedActor = {
      userId: assigned.managerId,
      role: "manager" as const,
    };
    const foreignActor = {
      userId: foreign.managerId,
      role: "manager" as const,
    };
    const assignedLessonIds: string[] = [];
    const foreignLessonIds: string[] = [];
    const deniedMetadata = [
      {
        idempotencyKey: `foreign-note-replace-${randomUUID()}`,
        requestId: `foreign-note-replace-request-${randomUUID()}`,
      },
      {
        idempotencyKey: `foreign-note-clear-${randomUUID()}`,
        requestId: `foreign-note-clear-request-${randomUUID()}`,
      },
    ];
    const createDto = (fixture: Awaited<ReturnType<typeof createFixture>>) => ({
      clientRef: { type: "student" as const, id: fixture.studentId },
      teacherId: fixture.teacherId,
      branchId: fixture.branchId,
      roomId: fixture.roomId,
      scheduledAt: "2026-07-27T07:00:00.000Z",
      durationMinutes: 60,
      isTrial: false,
      completionType: "standard.success",
      clientChargeType: "none" as const,
      clientChargeValue: 0,
      teacherCompensationType: "fixed" as const,
      teacherCompensationValue: 700,
      notes: "Исходная заметка",
      financialDecision: {
        settlementTypeKey: "free_lesson",
        teacherCompensationRuleKey: "none",
      },
    });
    try {
      const assignedLesson = await commands.create(
        assignedActor,
        createDto(assigned),
        {
          idempotencyKey: `assigned-note-create-${randomUUID()}`,
          requestId: `assigned-note-create-request-${randomUUID()}`,
        },
      );
      assignedLessonIds.push(assignedLesson.id);
      const inScope = await commands.update(
        assignedActor,
        assignedLesson.id,
        {
          expectedVersion: assignedLesson.version,
          notes: "Заметка своего филиала",
        },
        {
          idempotencyKey: `assigned-note-update-${randomUUID()}`,
          requestId: `assigned-note-update-request-${randomUUID()}`,
        },
      );
      expect(inScope.version).toBe(assignedLesson.version + 1);

      const foreignLesson = await commands.create(
        foreignActor,
        createDto(foreign),
        {
          idempotencyKey: `foreign-note-create-${randomUUID()}`,
          requestId: `foreign-note-create-request-${randomUUID()}`,
        },
      );
      foreignLessonIds.push(foreignLesson.id);
      const snapshot = () =>
        pool.query<{
          version: string;
          notes: string | null;
          aggregate_version: string;
          audits: string;
          outbox: string;
        }>(
          `select lesson.version::text as version, lesson.notes,
             aggregate.version::text as aggregate_version,
             (select count(*)::text from app.audit_events audit
               where audit.entity_type = 'lesson'
                 and audit.entity_id = lesson.id::text) as audits,
             (select count(*)::text from app.platform_outbox_events event
               where event.aggregate_type = 'schedule:lesson'
                 and event.aggregate_id = lesson.id::text) as outbox
           from app.lessons lesson
           join app.aggregate_versions aggregate
             on aggregate.aggregate_type = 'schedule:lesson'
            and aggregate.aggregate_id = lesson.id::text
           where lesson.id = $1`,
          [foreignLesson.id],
        );
      const before = (await snapshot()).rows[0]!;

      for (const [index, notes] of [
        "Подмена заметки чужого филиала",
        null,
      ].entries()) {
        let denied: HttpException | null = null;
        try {
          await commands.update(
            assignedActor,
            foreignLesson.id,
            {
              expectedVersion: foreignLesson.version,
              notes: notes as never,
            },
            deniedMetadata[index]!,
          );
        } catch (error) {
          if (error instanceof HttpException) denied = error;
          else throw error;
        }
        expect(denied?.getStatus()).toBe(404);
        expect(JSON.stringify(denied?.getResponse())).not.toContain(
          "currentVersion",
        );
      }
      await expect(
        commands.update(
          { userId: assignedAdmin.managerId, role: "admin" },
          foreignLesson.id,
          {
            expectedVersion: foreignLesson.version,
            notes: "Администратор чужого филиала",
          },
          {
            idempotencyKey: `admin-scope-denied-${randomUUID()}`,
            requestId: `admin-scope-denied-request-${randomUUID()}`,
          },
        ),
      ).rejects.toMatchObject({ status: 404 });

      expect((await snapshot()).rows[0]).toEqual(before);
      const deniedIdempotency = await pool.query<{ count: string }>(
        `select count(*)::text as count
         from app.idempotency_records
         where actor_key = $1
           and operation = 'schedule.lesson.update'
           and idempotency_key = any($2::text[])`,
        [
          `user:${assigned.managerId}`,
          deniedMetadata.map((item) => item.idempotencyKey),
        ],
      );
      expect(deniedIdempotency.rows[0]!.count).toBe("0");
    } finally {
      await cleanupFixture(pool, {
        ...foreign,
        actorKey: `user:${foreign.managerId}`,
        lessonIds: foreignLessonIds,
      });
      await cleanupFixture(pool, {
        ...assigned,
        actorKey: `user:${assigned.managerId}`,
        lessonIds: assignedLessonIds,
      });
      await cleanupFixture(pool, {
        ...assignedAdmin,
        actorKey: `user:${assignedAdmin.managerId}`,
        lessonIds: [],
      });
    }
  });

  it("returns 403 and preserves the Lesson on a direct Teacher mutation", async () => {
    const fixture = await createFixture(pool);
    const manager = { userId: fixture.managerId, role: "manager" as const };
    const teacher = {
      userId: fixture.teacherUserId,
      role: "teacher" as const,
    };
    const lessonIds: string[] = [];
    const metadata = (name: string) => ({
      idempotencyKey: `teacher-read-only-${name}-${randomUUID()}`,
      requestId: `teacher-read-only-request-${name}-${randomUUID()}`,
    });
    try {
      const lesson = await commands.create(
        manager,
        {
          clientRef: { type: "student", id: fixture.studentId },
          teacherId: fixture.teacherId,
          branchId: fixture.branchId,
          roomId: fixture.roomId,
          scheduledAt: "2026-07-27T07:00:00.000Z",
          durationMinutes: 60,
          isTrial: false,
          completionType: "standard.success",
          clientChargeType: "none",
          clientChargeValue: 0,
          teacherCompensationType: "fixed",
          teacherCompensationValue: 700,
          financialDecision: {
            settlementTypeKey: "free_lesson",
            teacherCompensationRuleKey: "none",
          },
        },
        metadata("create"),
      );
      lessonIds.push(lesson.id);

      let status: number | null = null;
      try {
        await commands.update(
          teacher,
          lesson.id,
          {
            expectedVersion: lesson.version,
            notes: "Teacher must not mutate the Lesson",
          },
          metadata("patch"),
        );
      } catch (error) {
        if (error instanceof HttpException) status = error.getStatus();
        else throw error;
      }
      expect(status).toBe(403);

      const persisted = await pool.query<{
        version: string;
        notes: string | null;
      }>(
        "select version::text as version, notes from app.lessons where id = $1",
        [lesson.id],
      );
      expect(persisted.rows[0]).toEqual({
        version: String(lesson.version),
        notes: null,
      });
    } finally {
      await cleanupFixture(pool, {
        ...fixture,
        actorKey: `user:${fixture.managerId}`,
        lessonIds,
      });
    }
  });

  it("allows one independent Manager winner and rejects direct drag bypasses", async () => {
    const fixture = await createFixture(pool);
    const secondManager = await pool.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, 'manager', now())
        returning id
      `,
      [`parity-manager-race-${randomUUID()}@example.test`],
    );
    const secondManagerId = secondManager.rows[0]!.id;
    const secondManagerProfile = await pool.query<{ id: string }>(
      `insert into app.profiles (user_id, first_name, last_name)
       values ($1, 'Parity', 'Second Manager') returning id`,
      [secondManagerId],
    );
    const secondManagerStaff = await pool.query<{ id: string }>(
      `insert into app.staff_members (profile_id, role)
       values ($1, 'manager') returning id`,
      [secondManagerProfile.rows[0]!.id],
    );
    await pool.query(
      `insert into app.user_crm_links (
         user_id, entity_type, entity_id, link_source, confirmed_at
       ) values ($1, 'staff', $2, 'manual_phone', now())`,
      [secondManagerId, secondManagerStaff.rows[0]!.id],
    );
    await pool.query(
      `insert into app.staff_branch_assignments (staff_member_id, branch_id)
       values ($1, $2)`,
      [secondManagerStaff.rows[0]!.id, fixture.branchId],
    );
    const leftActor = { userId: fixture.managerId, role: "manager" as const };
    const rightActor = { userId: secondManagerId, role: "manager" as const };
    const lessonIds: string[] = [];
    const metadata = (name: string) => ({
      idempotencyKey: `schedule-race-${name}-${randomUUID()}`,
      requestId: `schedule-race-request-${name}-${randomUUID()}`,
    });
    const base = {
      clientRef: { type: "student" as const, id: fixture.studentId },
      teacherId: fixture.teacherId,
      branchId: fixture.branchId,
      roomId: fixture.roomId,
      durationMinutes: 60,
      isTrial: false,
      completionType: "standard.success",
      clientChargeType: "none" as const,
      clientChargeValue: 0,
      teacherCompensationType: "fixed" as const,
      teacherCompensationValue: 700,
      financialDecision: {
        settlementTypeKey: "free_lesson",
        teacherCompensationRuleKey: "none",
      },
    };
    const leftMetadata = metadata("create-left");
    const rightMetadata = metadata("create-right");
    try {
      const concurrentCreates = await Promise.allSettled([
        commands.create(
          leftActor,
          { ...base, scheduledAt: "2026-07-27T07:00:00.000Z" },
          leftMetadata,
        ),
        commands.create(
          rightActor,
          { ...base, scheduledAt: "2026-07-27T07:00:00.000Z" },
          rightMetadata,
        ),
      ]);
      const acceptedCreate = concurrentCreates.filter(
        (
          result,
        ): result is PromiseFulfilledResult<
          Awaited<ReturnType<LessonCommandService["create"]>>
        > => result.status === "fulfilled",
      );
      const rejectedCreate = concurrentCreates.filter(
        (result): result is PromiseRejectedResult =>
          result.status === "rejected",
      );
      expect(acceptedCreate).toHaveLength(1);
      expect(rejectedCreate).toHaveLength(1);
      lessonIds.push(acceptedCreate[0]!.value.id);
      expect(rejectedCreate[0]!.reason).toMatchObject({ status: 422 });
      expect(rejectedCreate[0]!.reason).toBeInstanceOf(HttpException);
      const rejectedResponse = (
        rejectedCreate[0]!.reason as HttpException
      ).getResponse() as {
        code?: string;
        violations?: Array<{ code?: string }>;
      };
      expect(rejectedResponse.code).toBe("LESSON_CONSTRAINT_VIOLATIONS");
      expect(rejectedResponse.violations).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ code: "TEACHER_OVERLAP" }),
          expect.objectContaining({ code: "CLIENT_OVERLAP" }),
          expect.objectContaining({ code: "ROOM_OVERLAP" }),
        ]),
      );
      const atomicFacts = await pool.query<{
        lessons: string;
        snapshots: string;
        plans: string;
        revisions: string;
        versions: string;
        audits: string;
        outbox: string;
        idempotency: string;
      }>(
        `
          with winner as (
            select id
            from app.lessons
            where teacher_id = $1
              and room_id = $2
              and scheduled_at = '2026-07-27T07:00:00.000Z'
              and deleted_at is null
          )
          select
            (select count(*)::text from winner) as lessons,
            (select count(*)::text from app.lesson_snapshots
              where lesson_id in (select id from winner)) as snapshots,
            (select count(*)::text from app.lesson_settlement_plans
              where lesson_id in (select id from winner)) as plans,
            (select count(*)::text from app.lesson_settlement_plan_revisions
              where lesson_id in (select id from winner)) as revisions,
            (select count(*)::text from app.aggregate_versions
              where aggregate_type = 'schedule:lesson'
                and aggregate_id in (select id::text from winner)) as versions,
            (select count(*)::text from app.audit_events
              where action = 'crm.lesson_created'
                and entity_id in (select id::text from winner)) as audits,
            (select count(*)::text from app.platform_outbox_events
              where aggregate_type = 'schedule:lesson'
                and aggregate_id in (select id::text from winner)) as outbox,
            (select count(*)::text from app.idempotency_records
              where actor_key = any($3::text[])
                and operation = 'schedule.lesson.create'
                and idempotency_key = any($4::text[])) as idempotency
        `,
        [
          fixture.teacherId,
          fixture.roomId,
          [`user:${fixture.managerId}`, `user:${secondManagerId}`],
          [leftMetadata.idempotencyKey, rightMetadata.idempotencyKey],
        ],
      );
      expect(atomicFacts.rows[0]).toEqual({
        lessons: "1",
        snapshots: "1",
        plans: "1",
        revisions: "1",
        versions: "1",
        audits: "1",
        outbox: "1",
        idempotency: "1",
      });

      const left = await commands.create(
        leftActor,
        { ...base, scheduledAt: "2026-07-27T09:00:00.000Z" },
        metadata("drag-source-left"),
      );
      const right = await commands.create(
        leftActor,
        { ...base, scheduledAt: "2026-07-27T11:00:00.000Z" },
        metadata("drag-source-right"),
      );
      lessonIds.push(left.id, right.id);

      const concurrentDrags = await Promise.allSettled([
        commands.update(
          leftActor,
          left.id,
          {
            expectedVersion: left.version,
            scheduledAt: "2026-07-27T13:00:00.000Z",
          },
          metadata("drag-left"),
        ),
        commands.update(
          leftActor,
          right.id,
          {
            expectedVersion: right.version,
            scheduledAt: "2026-07-27T13:00:00.000Z",
          },
          metadata("drag-right"),
        ),
      ]);
      expect(
        concurrentDrags.filter((result) => result.status === "fulfilled"),
      ).toHaveLength(0);
      const rejectedDrag = concurrentDrags.filter(
        (result): result is PromiseRejectedResult =>
          result.status === "rejected",
      );
      expect(rejectedDrag).toHaveLength(2);
      expect(rejectedDrag[0]!.reason).toMatchObject({ status: 422 });
      expect(rejectedDrag[1]!.reason).toMatchObject({ status: 422 });

      const persisted = await pool.query<{
        at_target: string;
        at_sources: string;
      }>(
        `
          select
            count(*) filter (
              where scheduled_at = '2026-07-27T13:00:00.000Z'
            )::text as at_target,
            count(*) filter (
              where scheduled_at in (
                '2026-07-27T09:00:00.000Z',
                '2026-07-27T11:00:00.000Z'
              )
            )::text as at_sources
          from app.lessons
          where id = any($1::uuid[])
        `,
        [[left.id, right.id]],
      );
      expect(persisted.rows[0]).toEqual({
        at_target: "0",
        at_sources: "2",
      });
    } finally {
      await cleanupFixture(pool, {
        ...fixture,
        actorKey: `user:${fixture.managerId}`,
        extraActorKeys: [`user:${secondManagerId}`],
        extraActorUserIds: [secondManagerId],
        extraUserIds: [secondManagerId],
        extraStaffIds: [secondManagerStaff.rows[0]!.id],
        extraProfileIds: [secondManagerProfile.rows[0]!.id],
        lessonIds,
      });
    }
  });

  it("atomically previews and replaces a future lesson settlement plan", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const lessonIds: string[] = [];
    const subscription = await pool.query<{ id: string }>(
      `insert into app.subscriptions (
         student_id, lessons_total, lessons_used, starts_at, expires_at, status
       ) values ($1, 12, 0, current_date, current_date + 30, 'active')
       returning id`,
      [fixture.studentId],
    );
    const subscriptionId = subscription.rows[0]!.id;
    const metadata = (name: string) => ({
      idempotencyKey: `planned-settlement-${name}-${randomUUID()}`,
      requestId: `planned-settlement-request-${name}-${randomUUID()}`,
    });
    const scheduledAt = nextMondayAtTenMoscow();
    try {
      const lesson = await commands.create(
        actor,
        {
          clientRef: { type: "student", id: fixture.studentId },
          teacherId: fixture.teacherId,
          branchId: fixture.branchId,
          roomId: fixture.roomId,
          scheduledAt,
          durationMinutes: 60,
          isTrial: false,
          completionType: "standard.success",
          clientChargeType: "subscription",
          clientChargeValue: 1,
          subscriptionId,
          teacherCompensationType: "fixed",
          teacherCompensationValue: 700,
          financialDecision: {
            settlementTypeKey: "lesson",
            teacherCompensationRuleKey: "none",
          },
        },
        metadata("create"),
      );
      lessonIds.push(lesson.id);
      const change = {
        expectedVersion: lesson.version,
        financialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
        },
        reasonText: "Бесплатное занятие согласовано управляющим",
      };
      const preview = await commands.previewSettlementPlan(
        actor,
        lesson.id,
        change,
      );

      expect(preview).toMatchObject({
        canConfirm: true,
        reservationPreview: {
          before: [{ subscriptionId, units: "1.00" }],
          after: [],
        },
        financialPreview: {
          clientFacts: [{ amountMinor: "0", units: "0.00" }],
          teacherFact: { amountMinor: "0" },
        },
      });

      const commitMetadata = metadata("commit");
      const committed = await commands.updateSettlementPlan(
        actor,
        lesson.id,
        { ...change, previewToken: preview.previewToken, confirm: true },
        commitMetadata,
      );
      expect(committed).toMatchObject({ version: 2, replayed: false });
      await expect(
        commands.updateSettlementPlan(
          actor,
          lesson.id,
          { ...change, previewToken: preview.previewToken, confirm: true },
          metadata("stale"),
        ),
      ).rejects.toMatchObject({ status: 409 });
      await expect(
        commands.updateSettlementPlan(
          actor,
          lesson.id,
          { ...change, previewToken: preview.previewToken, confirm: true },
          commitMetadata,
        ),
      ).resolves.toMatchObject({ version: 2, replayed: true });

      const persisted = await pool.query<{
        version: string;
        settlement_type: string;
        revisions: string;
        active_reservations: string;
      }>(
        `select plan.version::text,
           plan.decision ->> 'settlementTypeKey' as settlement_type,
           (select count(*)::text from app.lesson_settlement_plan_revisions
             where lesson_id = plan.lesson_id) as revisions,
           (select count(*)::text from app.lesson_reservations
             where lesson_id = plan.lesson_id and state = 'reserved')
             as active_reservations
         from app.lesson_settlement_plans plan
         where plan.lesson_id = $1`,
        [lesson.id],
      );
      expect(persisted.rows[0]).toEqual({
        version: "2",
        settlement_type: "free_lesson",
        revisions: "2",
        active_reservations: "0",
      });
    } finally {
      await cleanupFixture(pool, {
        ...fixture,
        actorKey: `user:${fixture.managerId}`,
        lessonIds,
      });
    }
  });
});

function nextMondayAtTenMoscow() {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + ((8 - date.getUTCDay()) % 7 || 7));
  date.setUTCHours(7, 0, 0, 0);
  return date.toISOString();
}

async function violationResponse(work: () => Promise<unknown>) {
  try {
    await work();
    throw new Error("Expected lesson constraint violation.");
  } catch (error) {
    if (!(error instanceof HttpException)) throw error;
    const response = error.getResponse() as {
      code?: string;
      violations?: unknown[];
    };
    return {
      code: response.code,
      violations: response.violations,
    };
  }
}

async function expectCommandError(
  work: () => Promise<unknown>,
  expected: { code: string; fields?: string[]; field?: string },
) {
  try {
    await work();
    throw new Error(`Expected command error ${expected.code}.`);
  } catch (error) {
    if (!(error instanceof HttpException)) throw error;
    const response = error.getResponse() as {
      code?: string;
      fields?: string[];
      field?: string;
    };
    expect({
      code: response.code,
      ...(response.fields ? { fields: response.fields } : {}),
      ...(response.field ? { field: response.field } : {}),
    }).toEqual(expected);
  }
}

async function createFixture(
  pool: Pool,
  operationalRole: "manager" | "admin" = "manager",
) {
  const branch = await pool.query<{ id: string }>(
    `
      insert into app.branches (name, timezone_name)
      values ($1, 'Europe/Moscow')
      returning id
    `,
    [`Write parity ${randomUUID()}`],
  );
  const branchId = branch.rows[0]!.id;
  await pool.query(
    `
      insert into app.branch_hours (branch_id, weekday, open_local, close_local)
      values ($1, 1, '09:00', '18:00')
    `,
    [branchId],
  );
  const room = await pool.query<{ id: string }>(
    `
      insert into app.rooms (branch_id, name)
      values ($1, $2)
      returning id
    `,
    [branchId, `Parity room ${randomUUID()}`],
  );
  const users = await pool.query<{ id: string; role: string }>(
    `
      insert into app.users (email, role, email_verified_at)
      values
        ($1, $4::app.user_role, now()),
        ($2, 'teacher', now()),
        ($3, 'client', now())
      returning id, role::text as role
    `,
    [
      `parity-manager-${randomUUID()}@example.test`,
      `parity-teacher-${randomUUID()}@example.test`,
      `parity-client-${randomUUID()}@example.test`,
      operationalRole,
    ],
  );
  const managerId = users.rows.find((row) => row.role === operationalRole)!.id;
  const teacherUserId = users.rows.find((row) => row.role === "teacher")!.id;
  const clientUserId = users.rows.find((row) => row.role === "client")!.id;
  const profiles = await pool.query<{ id: string; user_id: string }>(
    `
      insert into app.profiles (user_id, first_name, last_name)
      values
        ($1, 'Parity', 'Manager'),
        ($2, 'Parity', 'Teacher'),
        ($3, 'Parity', 'Student')
      returning id, user_id
    `,
    [managerId, teacherUserId, clientUserId],
  );
  const managerProfileId = profiles.rows.find(
    (row) => row.user_id === managerId,
  )!.id;
  const teacherProfileId = profiles.rows.find(
    (row) => row.user_id === teacherUserId,
  )!.id;
  const studentProfileId = profiles.rows.find(
    (row) => row.user_id === clientUserId,
  )!.id;
  const managerStaff = await pool.query<{ id: string }>(
    `insert into app.staff_members (profile_id, role)
     values ($1, $2) returning id`,
    [managerProfileId, operationalRole],
  );
  await pool.query(
    `insert into app.user_crm_links (
       user_id, entity_type, entity_id, link_source, confirmed_at
     ) values ($1, 'staff', $2, 'manual_phone', now())`,
    [managerId, managerStaff.rows[0]!.id],
  );
  await pool.query(
    `insert into app.staff_branch_assignments (staff_member_id, branch_id)
     values ($1, $2)`,
    [managerStaff.rows[0]!.id, branchId],
  );
  const teacher = await pool.query<{ id: string }>(
    "insert into app.teachers (profile_id) values ($1) returning id",
    [teacherProfileId],
  );
  const teacherId = teacher.rows[0]!.id;
  await pool.query(
    `
      insert into app.teacher_branches (
        teacher_id, branch_id, active_from, active_until
      )
      values ($1, $2, '2026-01-01', '2100-12-31')
    `,
    [teacherId, branchId],
  );
  await pool.query(
    `
      insert into app.teacher_availability_rules (
        teacher_id, kind, available, timezone_name, weekday,
        local_start, local_end, valid_from, valid_until
      )
      values (
        $1, 'recurring', true, 'Europe/Moscow', 1,
        '09:00', '18:00', '2026-01-01', '2100-12-31'
      )
    `,
    [teacherId],
  );
  const student = await pool.query<{ id: string }>(
    `
      insert into app.students (profile_id, branch_id)
      values ($1, $2)
      returning id
    `,
    [studentProfileId, branchId],
  );
  const lead = await pool.query<{ id: string }>(
    `
      insert into app.leads (branch_id, first_name, last_name, phone)
      values ($1, 'Parity', 'Lead', $2)
      returning id
    `,
    [
      branchId,
      `+7999${Math.floor(Math.random() * 10_000_000)
        .toString()
        .padStart(7, "0")}`,
    ],
  );
  return {
    branchId,
    roomId: room.rows[0]!.id,
    teacherId,
    studentId: student.rows[0]!.id,
    leadId: lead.rows[0]!.id,
    managerId,
    managerStaffId: managerStaff.rows[0]!.id,
    teacherUserId,
    clientUserId,
    profileIds: profiles.rows.map((row) => row.id),
  };
}

async function cleanupFixture(
  pool: Pool,
  fixture: {
    branchId: string;
    roomId: string;
    teacherId: string;
    studentId: string;
    leadId: string;
    managerId: string;
    managerStaffId: string;
    teacherUserId: string;
    clientUserId: string;
    profileIds: string[];
    actorKey: string;
    extraActorKeys?: string[];
    extraActorUserIds?: string[];
    extraUserIds?: string[];
    extraStaffIds?: string[];
    extraProfileIds?: string[];
    lessonIds: string[];
  },
) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("set local session_replication_role = replica");
    await client.query(
      "delete from app.idempotency_records where actor_key = any($1::text[])",
      [[fixture.actorKey, ...(fixture.extraActorKeys ?? [])]],
    );
    await client.query(
      `
        delete from app.platform_outbox_events
        where aggregate_type = 'schedule:lesson'
          and aggregate_id = any($1::text[])
      `,
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.audit_events where actor_user_id = any($1::uuid[])",
      [[fixture.managerId, ...(fixture.extraActorUserIds ?? [])]],
    );
    await client.query(
      "delete from app.aggregate_versions where aggregate_type = 'schedule:lesson' and aggregate_id = any($1::text[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.lesson_reservations where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.lesson_settlement_plan_revisions where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.lesson_settlement_plans where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.lesson_snapshots where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query("delete from app.lessons where id = any($1::uuid[])", [
      fixture.lessonIds,
    ]);
    await client.query("delete from app.subscriptions where student_id = $1", [
      fixture.studentId,
    ]);
    await client.query("delete from app.students where id = $1", [
      fixture.studentId,
    ]);
    await client.query("delete from app.leads where id = $1", [fixture.leadId]);
    await client.query(
      "delete from app.teacher_availability_rules where teacher_id = $1",
      [fixture.teacherId],
    );
    await client.query(
      "delete from app.teacher_branches where teacher_id = $1",
      [fixture.teacherId],
    );
    await client.query("delete from app.teachers where id = $1", [
      fixture.teacherId,
    ]);
    await client.query("delete from app.rooms where id = $1", [fixture.roomId]);
    const staffIds = [fixture.managerStaffId, ...(fixture.extraStaffIds ?? [])];
    await client.query(
      "delete from app.staff_branch_assignments where staff_member_id = any($1::uuid[])",
      [staffIds],
    );
    await client.query(
      "delete from app.user_crm_links where user_id = any($1::uuid[]) and entity_type = 'staff'",
      [[fixture.managerId, ...(fixture.extraUserIds ?? [])]],
    );
    await client.query(
      "delete from app.staff_members where id = any($1::uuid[])",
      [staffIds],
    );
    await client.query("delete from app.profiles where id = any($1::uuid[])", [
      [...fixture.profileIds, ...(fixture.extraProfileIds ?? [])],
    ]);
    await client.query("delete from app.users where id = any($1::uuid[])", [
      [
        fixture.managerId,
        fixture.teacherUserId,
        fixture.clientUserId,
        ...(fixture.extraUserIds ?? []),
      ],
    ]);
    await client.query("delete from app.branch_hours where branch_id = $1", [
      fixture.branchId,
    ]);
    await client.query("delete from app.branches where id = $1", [
      fixture.branchId,
    ]);
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}
