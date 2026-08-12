import {
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "crypto";
import { Pool } from "pg";
import { AuditService } from "../../audit/audit.service";
import { ActorContext, UserRole } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { TimelineService } from "../timeline.service";
import { CommentSharingService } from "./comment-sharing.service";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
const parsedDatabaseUrl = new URL(testDatabaseUrl);
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(parsedDatabaseUrl.hostname)
) {
  throw new Error("Comment sharing tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Comment sharing (PostgreSQL)", () => {
  let database: DatabaseService;
  let sharing: CommentSharingService;
  let timeline: TimelineService;
  let realtime: { emitCrmChanged: jest.Mock };
  let actors: Record<string, ActorContext>;
  let studentId: string;
  let lessonId: string;
  const fixtureUserIds: string[] = [];
  const fixtureProfileIds: string[] = [];
  const fixtureTeacherIds: string[] = [];
  const commentIds: string[] = [];

  const requestId = () => `v4-comment-share:${randomUUID()}`;
  const idempotencyKey = () => `v4-comment-share-${randomUUID()}`;

  async function createActor(role: UserRole): Promise<ActorContext> {
    const user = await database.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, $2::app.user_role, now())
        returning id
      `,
      [`v4-comment-share-${randomUUID()}@example.test`, role],
    );
    const userId = user.rows[0]!.id;
    fixtureUserIds.push(userId);
    const profile = await database.query<{ id: string }>(
      `
        insert into app.profiles (user_id, first_name, last_name)
        values ($1, 'V4', $2)
        returning id
      `,
      [userId, role],
    );
    fixtureProfileIds.push(profile.rows[0]!.id);
    return { userId, role };
  }

  async function createComment(
    body: string,
    sharedWithTeacher = false,
  ): Promise<{ id: string; version: number }> {
    const result = await database.query<{
      id: string;
      version: number | string;
    }>(
      `
        insert into app.entity_comments (
          entity_type,
          entity_id,
          author_id,
          body,
          kind,
          shared_with_teacher
        )
        values (
          'student',
          $1,
          $2,
          $3,
          case when $4 then 'teacher_note' else 'admin_comment' end,
          $4
        )
        returning id, version
      `,
      [studentId, actors.admin.userId, body, sharedWithTeacher],
    );
    const row = result.rows[0]!;
    commentIds.push(row.id);
    return { id: row.id, version: Number(row.version) };
  }

  async function cleanupMutationEvidence(): Promise<void> {
    await database.query(
      `
        delete from app.idempotency_records
        where operation = 'crm.comment.teacher-sharing.set'
          and actor_key = any($1::text[])
      `,
      [fixtureUserIds],
    );
    await database.query(
      "delete from app.audit_events where request_id like 'v4-comment-share:%'",
    );
    await database.query(
      "delete from app.platform_outbox_events where request_id like 'v4-comment-share:%'",
    );
  }

  beforeAll(async () => {
    const migrationPool = new Pool({ connectionString: testDatabaseUrl });
    try {
      await new MigrationRunner(migrationPool).up();
    } finally {
      await migrationPool.end();
    }

    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    await database.query(`
      delete from app.idempotency_records
      where operation = 'crm.comment.teacher-sharing.set'
        and actor_key in (
          select id::text from app.users
          where email like 'v4-comment-share-%@example.test'
        );
      delete from app.audit_events
      where request_id like 'v4-comment-share:%';
      delete from app.platform_outbox_events
      where request_id like 'v4-comment-share:%';
      delete from app.aggregate_versions
      where aggregate_type = 'crm:comment'
        and aggregate_id in (
          select id::text from app.entity_comments
          where author_id in (
            select id from app.users
            where email like 'v4-comment-share-%@example.test'
          )
        );
      delete from app.entity_comments
      where author_id in (
        select id from app.users
        where email like 'v4-comment-share-%@example.test'
      );
      delete from app.lessons
      where created_by in (
        select id from app.users
        where email like 'v4-comment-share-%@example.test'
      );
      delete from app.teachers
      where profile_id in (
        select id from app.profiles
        where user_id in (
          select id from app.users
          where email like 'v4-comment-share-%@example.test'
        )
      );
      delete from app.students
      where profile_id in (
        select id from app.profiles
        where user_id in (
          select id from app.users
          where email like 'v4-comment-share-%@example.test'
        )
      );
      delete from app.aggregate_versions
      where aggregate_type = 'access:user'
        and aggregate_id in (
          select id::text from app.users
          where email like 'v4-comment-share-%@example.test'
        );
      delete from app.users
      where email like 'v4-comment-share-%@example.test';
    `);

    actors = {
      client: await createActor("client"),
      teacher: await createActor("teacher"),
      unrelatedTeacher: await createActor("teacher"),
      admin: await createActor("admin"),
      manager: await createActor("manager"),
      director: await createActor("director"),
      systemAdmin: await createActor("system_admin"),
    };

    const clientProfileId =
      fixtureProfileIds[fixtureUserIds.indexOf(actors.client.userId)]!;
    const student = await database.query<{ id: string }>(
      `
        insert into app.students (profile_id, status)
        values ($1, 'active')
        returning id
      `,
      [clientProfileId],
    );
    studentId = student.rows[0]!.id;

    for (const actorKey of ["teacher", "unrelatedTeacher"]) {
      const actor = actors[actorKey]!;
      const profileId =
        fixtureProfileIds[fixtureUserIds.indexOf(actor.userId)]!;
      const teacher = await database.query<{ id: string }>(
        `
          insert into app.teachers (profile_id, status)
          values ($1, 'active')
          returning id
        `,
        [profileId],
      );
      fixtureTeacherIds.push(teacher.rows[0]!.id);
    }

    const lesson = await database.query<{ id: string }>(
      `
        insert into app.lessons (
          student_id,
          teacher_id,
          scheduled_at,
          created_by
        )
        values ($1, $2, now(), $3)
        returning id
      `,
      [studentId, fixtureTeacherIds[0], actors.admin.userId],
    );
    lessonId = lesson.rows[0]!.id;

    realtime = { emitCrmChanged: jest.fn() };
    sharing = new CommentSharingService(
      database,
      new PlatformIntegrityService(database, new PlatformIntegrityRepository()),
      realtime as unknown as RealtimeBus,
    );
    timeline = new TimelineService(
      database,
      new CrmPolicy(),
      { record: jest.fn() } as unknown as AuditService,
      realtime as unknown as RealtimeBus,
    );
  });

  beforeEach(() => {
    realtime.emitCrmChanged.mockClear();
  });

  afterEach(async () => {
    await cleanupMutationEvidence();
    if (commentIds.length > 0) {
      await database.query(
        `
          delete from app.entity_comments
          where id = any($1::uuid[])
        `,
        [commentIds],
      );
      await database.query(
        `
          delete from app.aggregate_versions
          where aggregate_type = 'crm:comment'
            and aggregate_id = any($1::text[])
        `,
        [commentIds],
      );
      commentIds.length = 0;
    }
  });

  afterAll(async () => {
    await cleanupMutationEvidence();
    await database.query("delete from app.lessons where id = $1", [lessonId]);
    await database.query(
      "delete from app.teachers where id = any($1::uuid[])",
      [fixtureTeacherIds],
    );
    await database.query("delete from app.students where id = $1", [studentId]);
    await database.query(
      `
        delete from app.aggregate_versions
        where aggregate_type = 'access:user'
          and aggregate_id = any($1::text[])
      `,
      [fixtureUserIds],
    );
    await database.query("delete from app.users where id = any($1::uuid[])", [
      fixtureUserIds,
    ]);
    await database.onModuleDestroy();
  });

  it("returns only explicitly shared comments to an assigned teacher", async () => {
    await createComment("HIDDEN-COMMENT-BODY", false);
    const shared = await createComment("SHARED-COMMENT-BODY", true);

    const result = await timeline.listComments(actors.teacher, {
      entityType: "student",
      entityId: studentId,
      limit: 20,
    });

    expect(result.items).toHaveLength(1);
    expect(result.items[0]).toMatchObject({
      id: shared.id,
      body: "SHARED-COMMENT-BODY",
      sharedWithTeacher: true,
      version: 1,
    });
    expect(JSON.stringify(result)).not.toContain("HIDDEN-COMMENT-BODY");
    const clientResult = await timeline.listComments(actors.client, {
      entityType: "student",
      entityId: studentId,
      limit: 20,
    });
    expect(clientResult.items).toEqual([]);
    expect(JSON.stringify(clientResult)).not.toContain("COMMENT-BODY");
    await expect(
      timeline.listComments(actors.unrelatedTeacher, {
        entityType: "student",
        entityId: studentId,
        limit: 20,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it.each(["admin", "manager", "director", "systemAdmin"])(
    "allows %s to toggle once with one audit and body-free event",
    async (actorKey) => {
      const body = `PRIVATE-BODY-${actorKey}`;
      const comment = await createComment(body, false);
      const mutationRequestId = requestId();
      const mutationIdempotencyKey = idempotencyKey();
      const command = {
        commentId: comment.id,
        sharedWithTeacher: true,
        expectedVersion: 1,
        reasonCode: `test.${actorKey}`,
        requestId: mutationRequestId,
        idempotencyKey: mutationIdempotencyKey,
      };

      const first = await sharing.setTeacherSharing(actors[actorKey]!, command);
      const replay = await sharing.setTeacherSharing(
        actors[actorKey]!,
        command,
      );

      expect(first).toMatchObject({
        replayed: false,
        version: 2,
        resultRef: {
          entityId: comment.id,
          sharedWithTeacher: true,
          version: 2,
        },
      });
      expect(replay).toMatchObject({ replayed: true, version: 2 });
      expect(realtime.emitCrmChanged).toHaveBeenCalledTimes(1);
      expect(realtime.emitCrmChanged).toHaveBeenCalledWith({
        entity: "comment",
        action: "updated",
        id: comment.id,
      });

      const evidence = await database.query<{
        audit_count: number | string;
        audit_reason_text: string | null;
        outbox_count: number | string;
        event_payload: Record<string, unknown>;
        shared_with_teacher: boolean;
        version: number | string;
      }>(
        `
          select
            (
              select count(*)
              from app.audit_events
              where request_id = $1
                and action = 'crm.comment_teacher_sharing_changed'
            ) as audit_count,
            (
              select reason_text
              from app.audit_events
              where request_id = $1
                and action = 'crm.comment_teacher_sharing_changed'
              limit 1
            ) as audit_reason_text,
            (
              select count(*)
              from app.platform_outbox_events
              where request_id = $1
            ) as outbox_count,
            (
              select payload
              from app.platform_outbox_events
              where request_id = $1
              limit 1
            ) as event_payload,
            comment.shared_with_teacher,
            comment.version
          from app.entity_comments comment
          where comment.id = $2
        `,
        [mutationRequestId, comment.id],
      );
      expect(evidence.rows[0]).toMatchObject({
        audit_count: "1",
        audit_reason_text: "Комментарий опубликован преподавателю",
        outbox_count: "1",
        event_payload: {
          entityId: comment.id,
          changedFields: ["sharedWithTeacher"],
        },
        shared_with_teacher: true,
        version: "2",
      });
      expect(JSON.stringify(evidence.rows[0])).not.toContain(body);
    },
  );

  it.each(["teacher", "client"])(
    "denies %s without partial writes",
    async (actorKey) => {
      const comment = await createComment(`DENIED-${actorKey}`, false);
      const mutationRequestId = requestId();
      await expect(
        sharing.setTeacherSharing(actors[actorKey]!, {
          commentId: comment.id,
          sharedWithTeacher: true,
          expectedVersion: 1,
          reasonCode: `test.denied.${actorKey}`,
          requestId: mutationRequestId,
          idempotencyKey: idempotencyKey(),
        }),
      ).rejects.toBeInstanceOf(ForbiddenException);

      const state = await database.query<{
        shared_with_teacher: boolean;
        version: number | string;
        evidence_count: number | string;
      }>(
        `
          select
            comment.shared_with_teacher,
            comment.version,
            (
              select count(*) from app.audit_events where request_id = $2
            ) + (
              select count(*) from app.platform_outbox_events where request_id = $2
            ) as evidence_count
          from app.entity_comments comment
          where comment.id = $1
        `,
        [comment.id, mutationRequestId],
      );
      expect(state.rows[0]).toMatchObject({
        shared_with_teacher: false,
        version: "1",
        evidence_count: "0",
      });
    },
  );

  it("rejects a stale version and rolls back audit, outbox, and row changes", async () => {
    const comment = await createComment("STALE-PRIVATE-BODY", false);
    await sharing.setTeacherSharing(actors.admin, {
      commentId: comment.id,
      sharedWithTeacher: true,
      expectedVersion: 1,
      reasonCode: "test.initial",
      requestId: requestId(),
      idempotencyKey: idempotencyKey(),
    });
    const staleRequestId = requestId();

    await expect(
      sharing.setTeacherSharing(actors.manager, {
        commentId: comment.id,
        sharedWithTeacher: false,
        expectedVersion: 1,
        reasonCode: "test.stale",
        requestId: staleRequestId,
        idempotencyKey: idempotencyKey(),
      }),
    ).rejects.toBeInstanceOf(ConflictException);

    const state = await database.query<{
      shared_with_teacher: boolean;
      version: number | string;
      evidence_count: number | string;
    }>(
      `
        select
          comment.shared_with_teacher,
          comment.version,
          (
            select count(*) from app.audit_events where request_id = $2
          ) + (
            select count(*) from app.platform_outbox_events where request_id = $2
          ) as evidence_count
        from app.entity_comments comment
        where comment.id = $1
      `,
      [comment.id, staleRequestId],
    );
    expect(state.rows[0]).toMatchObject({
      shared_with_teacher: true,
      version: "2",
      evidence_count: "0",
    });
  });
});
