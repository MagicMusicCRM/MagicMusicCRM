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
  const lessonIds = [randomUUID(), randomUUID()];

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
      [...lessonIds, leadId, teacherId, ...branchIds, ...roomIds],
    );
  });

  afterAll(async () => {
    await pool.query("delete from app.user_crm_links where user_id = $1", [userId]);
    await pool.query("delete from app.teacher_branches where teacher_id = $1", [teacherId]);
    await pool.query("delete from app.lessons where id = any($1::uuid[])", [lessonIds]);
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
    expect(dryRun.summary.reviewQueue).toBe(2);

    const before = await pool.query<{ count: string }>(
      "select count(*)::text as count from app.user_crm_links where user_id = $1",
      [userId],
    );
    expect(before.rows[0]?.count).toBe("0");

    const first = await runBackfill(pool, "apply");
    expect(first.summary.applied).toBe(3);
    expect(first.summary.reviewQueue).toBe(2);

    const second = await runBackfill(pool, "apply");
    expect(second.summary).toMatchObject({
      candidates: 0,
      applied: 0,
      reviewQueue: 2,
    });
  });
});
