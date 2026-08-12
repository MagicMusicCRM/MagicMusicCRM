import { randomUUID } from "crypto";
import { Pool } from "pg";
import { runBackfill } from "./v4-backfill";

const databaseUrl = process.env.V4_PLATFORM_TEST_DATABASE_URL
  ?? process.env.DATABASE_URL
  ?? "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";

describe("T8.3.1 production backfill", () => {
  const pool = new Pool({ connectionString: databaseUrl, max: 2 });
  const userId = randomUUID();
  let profileId = "";
  let staffId = "";
  let teacherId = "";
  const branchIds = [randomUUID(), randomUUID()];
  const roomIds = [randomUUID(), randomUUID()];
  const leadId = randomUUID();
  const groupId = randomUUID();
  const studentIds = [randomUUID(), randomUUID()];
  const lessonIds = [randomUUID(), randomUUID(), randomUUID(), randomUUID()];

  beforeAll(async () => {
    await pool.query(
      `insert into app.users (
         id, email, role, is_app_account, profile_completed
       ) values ($1, $2, 'manager', true, true)`,
      [userId, `v4-backfill-${userId}@example.invalid`],
    );
    const profile = await pool.query<{ id: string }>(
      `insert into app.profiles (user_id, first_name, last_name)
       values ($1, 'Backfill', 'Fixture') returning id`,
      [userId],
    );
    profileId = profile.rows[0]!.id;
    const staff = await pool.query<{ id: string }>(
      `insert into app.staff_members (profile_id, role, status)
       values ($1, 'manager', 'working') returning id`,
      [profileId],
    );
    staffId = staff.rows[0]!.id;
    const teacher = await pool.query<{ id: string }>(
      `insert into app.teachers (profile_id, status)
       values ($1, 'active') returning id`,
      [profileId],
    );
    teacherId = teacher.rows[0]!.id;
    await pool.query(
      `insert into app.branches (id, name) values
         ($1, 'Backfill branch A'), ($2, 'Backfill branch B')`,
      branchIds,
    );
    await pool.query(
      `insert into app.rooms (id, branch_id, name) values
         ($1, $3, 'Room A'), ($2, $4, 'Room B')`,
      [...roomIds, ...branchIds],
    );
    await pool.query(
      `insert into app.leads (id, first_name) values ($1, 'Backfill')`,
      [leadId],
    );
    await pool.query(
      `insert into app.lessons (
         id, lead_id, teacher_id, branch_id, room_id, scheduled_at, is_trial
       ) values
         ($1, $3, $4, $5, $7, now() + interval '30 days', true),
         ($2, $3, $4, $6, $8, now() + interval '31 days', true)`,
      [lessonIds[0], lessonIds[1], leadId, teacherId, ...branchIds, ...roomIds],
    );
    await pool.query(
      `insert into app.students (id, custom_data) values
         ($1, '{"individualPrice":800}'::jsonb),
         ($2, '{"individualPrice":800}'::jsonb)`,
      studentIds,
    );
    await pool.query(
      `insert into app.groups (id, teacher_id, branch_id, room_id, name, price_per_lesson)
       values ($1, $2, $3, $4, 'Backfill group', 800)`,
      [groupId, teacherId, branchIds[0], roomIds[0]],
    );
    await pool.query(
      `insert into app.group_students (group_id, student_id, joined_at)
       values ($1, $2, now() - interval '1 day'),
              ($1, $3, now() - interval '1 day')`,
      [groupId, ...studentIds],
    );
    await pool.query(
      `insert into app.teacher_rates (teacher_id, rate, effective_from)
       values ($1, 600, current_date - 1)`,
      [teacherId],
    );
    await pool.query(
      `insert into app.lessons (
         id, group_id, teacher_id, branch_id, room_id, scheduled_at
       ) values ($1, $2, $3, $4, $5, now() + interval '32 days')`,
      [lessonIds[2], groupId, teacherId, branchIds[0], roomIds[0]],
    );
    await pool.query(
      `insert into app.lessons (
         id, lead_id, teacher_id, branch_id, room_id, scheduled_at, is_trial
       ) values ($1, $2, $3, $4, $5, now() + interval '33 days', false)`,
      [lessonIds[3], leadId, teacherId, branchIds[0], roomIds[0]],
    );
  });

  afterAll(async () => {
    await pool.query("delete from app.user_crm_links where user_id = $1", [userId]);
    await pool.query("delete from app.teacher_branches where teacher_id = $1", [teacherId]);
    const cleanup = await pool.connect();
    try {
      await cleanup.query("begin");
      await cleanup.query("set local session_replication_role = replica");
      await cleanup.query("delete from app.lesson_snapshot_participants where lesson_id = any($1::uuid[])", [lessonIds]);
      await cleanup.query("delete from app.lesson_snapshots where lesson_id = any($1::uuid[])", [lessonIds]);
      await cleanup.query("delete from app.lessons where id = any($1::uuid[])", [lessonIds]);
      await cleanup.query("commit");
    } catch (error) {
      await cleanup.query("rollback");
      throw error;
    } finally {
      cleanup.release();
    }
    await pool.query("delete from app.teacher_rates where teacher_id = $1", [teacherId]);
    await pool.query("delete from app.group_students where group_id = $1", [groupId]);
    await pool.query("delete from app.groups where id = $1", [groupId]);
    await pool.query("delete from app.students where id = any($1::uuid[])", [studentIds]);
    await pool.query("delete from app.leads where id = $1", [leadId]);
    await pool.query("delete from app.rooms where id = any($1::uuid[])", [roomIds]);
    await pool.query("delete from app.branches where id = any($1::uuid[])", [branchIds]);
    if (teacherId) {
      await pool.query("delete from app.teachers where id = $1", [teacherId]);
    }
    if (staffId) {
      await pool.query("delete from app.staff_members where id = $1", [staffId]);
    }
    if (profileId) {
      await pool.query("delete from app.profiles where id = $1", [profileId]);
    }
    await pool.query("delete from app.users where id = $1", [userId]);
    await pool.end();
  });

  it("plans every evidenced branch, applies once, and is restartable", async () => {
    const dryRun = await runBackfill(pool, "dry-run");
    expect(dryRun.candidates).toContainEqual({
      kind: "access-link",
      entityId: userId,
      relatedId: staffId,
    });
    expect(dryRun.candidates).toEqual(expect.arrayContaining(
      branchIds.map((branchId) => ({
        kind: "teacher-branch",
        entityId: teacherId,
        relatedId: branchId,
      })),
    ));
    expect(dryRun.candidates).toEqual(expect.arrayContaining(
      lessonIds.slice(0, 2).map((lessonId) => ({
        kind: "lesson-snapshot",
        entityId: lessonId,
        relatedId: leadId,
      })),
    ));
    expect(dryRun.candidates).toContainEqual({
      kind: "lesson-snapshot",
      entityId: lessonIds[2],
      relatedId: groupId,
    });
    expect(dryRun.manualMappingTable).toContainEqual({
      checkId: "schedule.future-snapshot-incomplete",
      entityId: lessonIds[3],
      relatedId: leadId,
      reason: "personal_account_price_missing",
    });
    expect(dryRun.summary.reviewQueue).toBe(1);

    const before = await pool.query<{ count: string }>(
      "select count(*)::text as count from app.user_crm_links where user_id = $1",
      [userId],
    );
    expect(before.rows[0]?.count).toBe("0");

    const first = await runBackfill(pool, "apply");
    expect(first.summary.applied).toBe(dryRun.summary.candidates);
    expect(first.summary.applied).toBeGreaterThanOrEqual(6);
    expect(first.summary.reviewQueue).toBe(1);

    const second = await runBackfill(pool, "apply");
    expect(second.summary).toMatchObject({
      candidates: 0,
      applied: 0,
      reviewQueue: 1,
    });
    const snapshots = await pool.query<{ count: string }>(
      `select count(*)::text as count from app.lesson_snapshots
       where lesson_id = any($1::uuid[]) and validation_state = 'valid'`,
      [lessonIds],
    );
    expect(snapshots.rows[0]?.count).toBe("3");
    const participants = await pool.query<{ count: string }>(
      `select count(*)::text as count from app.lesson_snapshot_participants
       where lesson_id = $1`,
      [lessonIds[2]],
    );
    expect(participants.rows[0]?.count).toBe("2");
  });
});
