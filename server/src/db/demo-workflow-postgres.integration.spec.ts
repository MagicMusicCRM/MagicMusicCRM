import { PGlite } from "@electric-sql/pglite";
import { promises as fs } from "node:fs";
import * as path from "node:path";
import { AuditService } from "../audit/audit.service";
import { AttendanceService } from "../crm/attendance.service";
import { DatabaseService } from "./database.service";
import { NotificationsService } from "../notifications/notifications.service";

jest.setTimeout(60_000);

type EmbeddedClient = {
  query: <T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    params?: unknown[],
  ) => Promise<{ rows: T[] }>;
};

const clientFor = (db: PGlite): EmbeddedClient => ({
  query: async <T extends Record<string, unknown>>(
    sql: string,
    params?: unknown[],
  ) => {
    const result = await db.query<T>(sql, params);
    return { rows: result.rows };
  },
});

const databaseFor = (db: PGlite): DatabaseService => {
  const client = clientFor(db);
  return {
    query: client.query,
    transaction: async <T>(work: (executor: EmbeddedClient) => Promise<T>) => {
      await db.exec("begin");
      try {
        const value = await work(client);
        await db.exec("commit");
        return value;
      } catch (error) {
        await db.exec("rollback");
        throw error;
      }
    },
  } as unknown as DatabaseService;
};

describe("T9.1 schema-backed PostgreSQL invariants", () => {
  it("applies migration 0072 and enforces lead-homework/conversion/token constraints", async () => {
    const db = new PGlite();
    try {
      await db.exec(`
        create schema app;
        create table app.leads (id uuid primary key);
        create table app.students (id uuid primary key);
        create table app.lesson_homeworks (
          id uuid primary key,
          student_id uuid not null references app.students(id),
          deleted_at timestamptz
        );
        create table app.subscriptions (id uuid primary key);
        create table app.notification_devices (
          id uuid primary key,
          token_hash text not null,
          enabled boolean not null default true,
          last_seen_at timestamptz not null default now(),
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now()
        );
        insert into app.students values
          ('00000000-0000-0000-0000-000000000101');
        insert into app.leads values
          ('00000000-0000-0000-0000-000000000201'),
          ('00000000-0000-0000-0000-000000000202');
        insert into app.notification_devices (id, token_hash, enabled, last_seen_at)
        values
          ('00000000-0000-0000-0000-000000000301', 'same-token', true, now() - interval '1 hour'),
          ('00000000-0000-0000-0000-000000000302', 'same-token', true, now());
      `);
      const migration = await fs.readFile(
        path.resolve(
          process.cwd(),
          "db/migrations/0072_demo_workflow_invariants.up.sql",
        ),
        "utf8",
      );
      await db.exec(migration);

      const enabled = await db.query<{ id: string }>(
        "select id from app.notification_devices where enabled order by id",
      );
      expect(enabled.rows.map((row) => row.id)).toEqual([
        "00000000-0000-0000-0000-000000000302",
      ]);

      await db.query(
        `insert into app.lesson_homeworks (id, lead_id)
         values ($1, $2)`,
        [
          "00000000-0000-0000-0000-000000000401",
          "00000000-0000-0000-0000-000000000201",
        ],
      );
      await expect(
        db.query(
          `insert into app.lesson_homeworks (id, student_id, lead_id)
           values ($1, $2, $3)`,
          [
            "00000000-0000-0000-0000-000000000402",
            "00000000-0000-0000-0000-000000000101",
            "00000000-0000-0000-0000-000000000202",
          ],
        ),
      ).rejects.toThrow();

      await db.query(
        "insert into app.subscriptions (id, conversion_lead_id) values ($1, $2)",
        [
          "00000000-0000-0000-0000-000000000501",
          "00000000-0000-0000-0000-000000000202",
        ],
      );
      await expect(
        db.query(
          "insert into app.subscriptions (id, conversion_lead_id) values ($1, $2)",
          [
            "00000000-0000-0000-0000-000000000502",
            "00000000-0000-0000-0000-000000000202",
          ],
        ),
      ).rejects.toThrow();

      await db.query("delete from app.leads where id = $1", [
        "00000000-0000-0000-0000-000000000201",
      ]);
      const cascaded = await db.query<{ count: string }>(
        "select count(*)::text as count from app.lesson_homeworks where id = $1",
        ["00000000-0000-0000-0000-000000000401"],
      );
      expect(cascaded.rows[0].count).toBe("0");
    } finally {
      await db.close();
    }
  });

  it("charges an ordinary lesson exactly once and never charges a trial", async () => {
    const db = new PGlite();
    try {
      await db.exec(`
        create schema app;
        create table app.profiles (
          id uuid primary key,
          user_id uuid,
          first_name text,
          last_name text,
          deleted_at timestamptz
        );
        create table app.teachers (
          id uuid primary key,
          profile_id uuid,
          deleted_at timestamptz
        );
        create table app.students (
          id uuid primary key,
          profile_id uuid,
          deleted_at timestamptz
        );
        create table app.lessons (
          id uuid primary key,
          student_id uuid,
          group_id uuid,
          teacher_id uuid,
          duration_minutes integer,
          is_trial boolean not null default false,
          status text not null default 'scheduled',
          updated_at timestamptz not null default now(),
          deleted_at timestamptz
        );
        create table app.group_students (
          group_id uuid,
          student_id uuid,
          left_at timestamptz
        );
        create table app.lesson_participation (
          id uuid primary key default gen_random_uuid(),
          lesson_id uuid not null,
          student_id uuid not null,
          status text not null,
          pass_reason text,
          attendance_kind text not null default 'attended',
          charge_share numeric(4,3) not null default 1,
          charged_hours numeric(6,2) not null default 0,
          subscription_id uuid,
          unique (lesson_id, student_id)
        );
        create table app.subscriptions (
          id uuid primary key,
          student_id uuid not null,
          lessons_total numeric(8,2) not null,
          lessons_used numeric(8,2) not null default 0,
          starts_at date,
          expires_at date,
          status text not null,
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now()
        );
        create table app.family_members (
          family_id uuid,
          entity_type text,
          entity_id uuid,
          deleted_at timestamptz
        );
        insert into app.profiles (id, first_name)
        values ('00000000-0000-0000-0000-000000000601', 'Demo');
        insert into app.students values
          ('00000000-0000-0000-0000-000000000602',
           '00000000-0000-0000-0000-000000000601', null);
        insert into app.lessons
          (id, student_id, duration_minutes, is_trial)
        values
          ('00000000-0000-0000-0000-000000000603',
           '00000000-0000-0000-0000-000000000602', 60, false),
          ('00000000-0000-0000-0000-000000000604',
           '00000000-0000-0000-0000-000000000602', 60, true);
        insert into app.subscriptions
          (id, student_id, lessons_total, lessons_used, status)
        values
          ('00000000-0000-0000-0000-000000000605',
           '00000000-0000-0000-0000-000000000602', 8, 0, 'active');
      `);

      const database = databaseFor(db);
      const service = new AttendanceService(
        database,
        { record: jest.fn().mockResolvedValue(undefined) } as unknown as AuditService,
        { notifyUser: jest.fn() } as unknown as NotificationsService,
      );
      const actor = { userId: "admin-a", role: "admin" as const };
      const studentId = "00000000-0000-0000-0000-000000000602";
      const ordinaryId = "00000000-0000-0000-0000-000000000603";
      const trialId = "00000000-0000-0000-0000-000000000604";

      await service.upsertLessonAttendance(actor, ordinaryId, {
        items: [{ studentId, kind: "attended" }],
      });
      await service.upsertLessonAttendance(actor, ordinaryId, {
        items: [{ studentId, kind: "attended" }],
      });
      await service.upsertLessonAttendance(actor, trialId, {
        items: [{ studentId, kind: "attended" }],
      });

      const usage = await db.query<{ lessons_used: string }>(
        "select lessons_used::text from app.subscriptions where id = $1",
        ["00000000-0000-0000-0000-000000000605"],
      );
      expect(usage.rows[0].lessons_used).toBe("1.00");
      const charges = await db.query<{
        lesson_id: string;
        charged_hours: string;
      }>(
        `select lesson_id, charged_hours::text
         from app.lesson_participation order by lesson_id`,
      );
      expect(charges.rows).toEqual([
        { lesson_id: ordinaryId, charged_hours: "1.00" },
        { lesson_id: trialId, charged_hours: "0.00" },
      ]);
    } finally {
      await db.close();
    }
  });
});
