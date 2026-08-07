import { PGlite } from "@electric-sql/pglite";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { FinanceService } from "./finance.service";

type EmbeddedClient = {
  query: <T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    params?: unknown[],
  ) => Promise<{ rows: T[] }>;
};

const databaseFor = (db: PGlite): DatabaseService => {
  const query: EmbeddedClient["query"] = async <
    T extends Record<string, unknown> = Record<string, unknown>,
  >(
    sql: string,
    params?: unknown[],
  ) => {
    const result = await db.query<T>(sql, params);
    return { rows: result.rows };
  };
  return { query } as unknown as DatabaseService;
};

describe("FinanceService subscription-backed lesson costs", () => {
  it("prices charged hours from the linked sale and preserves payer, partial, free and trial semantics", async () => {
    const db = new PGlite();
    try {
      await db.exec(`
        create schema app;
        create table app.profiles (
          id uuid primary key, first_name text, last_name text, phone text,
          deleted_at timestamptz
        );
        create table app.students (
          id uuid primary key, profile_id uuid, custom_data jsonb not null default '{}',
          updated_at timestamptz not null default now(), deleted_at timestamptz
        );
        create table app.groups (
          id uuid primary key, price_per_lesson numeric, deleted_at timestamptz
        );
        create table app.subscription_packages (
          id uuid primary key, price numeric not null
        );
        create table app.payments (
          id uuid primary key, student_id uuid not null, amount numeric not null,
          payment_date timestamptz not null default now(),
          created_at timestamptz not null default now(), deleted_at timestamptz
        );
        create table app.subscriptions (
          id uuid primary key, student_id uuid not null, package_id uuid,
          payment_id uuid, lessons_total numeric not null
        );
        create table app.lessons (
          id uuid primary key, student_id uuid, group_id uuid,
          status text not null, is_trial boolean not null default false,
          updated_at timestamptz not null default now(), deleted_at timestamptz
        );
        create table app.lesson_participation (
          id uuid primary key, lesson_id uuid not null, student_id uuid not null,
          attendance_kind text not null, charge_share numeric not null default 1,
          charged_hours numeric not null default 0, subscription_id uuid
        );
        create table app.account_adjustments (
          student_id uuid not null, amount numeric not null,
          occurred_at timestamptz not null default now(),
          status text not null default 'paid', deleted_at timestamptz
        );
        create view app.commerce_ordinary_payments as
          select * from app.payments;
        create view app.commerce_ordinary_account_adjustments as
          select * from app.account_adjustments;

        insert into app.profiles (id, first_name) values
          ('00000000-0000-0000-0000-000000000101', 'Owner'),
          ('00000000-0000-0000-0000-000000000102', 'Payer'),
          ('00000000-0000-0000-0000-000000000103', 'Child'),
          ('00000000-0000-0000-0000-000000000104', 'Legacy');
        insert into app.students (id, profile_id, custom_data) values
          ('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000101', '{}'),
          ('00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000102', '{}'),
          ('00000000-0000-0000-0000-000000000203', '00000000-0000-0000-0000-000000000103', '{}'),
          ('00000000-0000-0000-0000-000000000204', '00000000-0000-0000-0000-000000000104', '{"individualPrice":2500}');

        -- The package was edited later to 32k; the issuance payment remains the
        -- historical 24k sale snapshot, therefore one charged hour is 3k.
        insert into app.subscription_packages (id, price) values
          ('00000000-0000-0000-0000-000000000301', 32000),
          ('00000000-0000-0000-0000-000000000302', 16000);
        insert into app.payments (id, student_id, amount) values
          ('00000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000201', 24000),
          ('00000000-0000-0000-0000-000000000402', '00000000-0000-0000-0000-000000000202', 16000);
        insert into app.subscriptions
          (id, student_id, package_id, payment_id, lessons_total) values
          ('00000000-0000-0000-0000-000000000501', '00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000401', 8),
          ('00000000-0000-0000-0000-000000000502', '00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000402', 8);

        insert into app.lessons (id, student_id, status, is_trial) values
          ('00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000201', 'completed', false),
          ('00000000-0000-0000-0000-000000000602', '00000000-0000-0000-0000-000000000201', 'completed', true),
          ('00000000-0000-0000-0000-000000000603', '00000000-0000-0000-0000-000000000201', 'completed', false),
          ('00000000-0000-0000-0000-000000000604', '00000000-0000-0000-0000-000000000203', 'completed', false),
          ('00000000-0000-0000-0000-000000000605', '00000000-0000-0000-0000-000000000204', 'completed', false);
        insert into app.lesson_participation
          (id, lesson_id, student_id, attendance_kind, charge_share, charged_hours, subscription_id) values
          ('00000000-0000-0000-0000-000000000701', '00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000201', 'attended', 1, 1, '00000000-0000-0000-0000-000000000501'),
          -- Trial evidence is never charged, even if corrupt legacy data kept a link.
          ('00000000-0000-0000-0000-000000000702', '00000000-0000-0000-0000-000000000602', '00000000-0000-0000-0000-000000000201', 'attended', 1, 1, '00000000-0000-0000-0000-000000000501'),
          ('00000000-0000-0000-0000-000000000703', '00000000-0000-0000-0000-000000000603', '00000000-0000-0000-0000-000000000201', 'free_lesson', 1, 0, null),
          -- A family/third-party subscription pays for the child: half an hour at 2k/hour.
          ('00000000-0000-0000-0000-000000000704', '00000000-0000-0000-0000-000000000604', '00000000-0000-0000-0000-000000000203', 'partially_paid', 0.5, 0.5, '00000000-0000-0000-0000-000000000502'),
          -- Legacy participation without subscription keeps the old price fallback.
          ('00000000-0000-0000-0000-000000000705', '00000000-0000-0000-0000-000000000605', '00000000-0000-0000-0000-000000000204', 'partially_paid', 0.4, 0, null);
      `);

      const policy = { assertCanReadSchoolFinance: jest.fn() };
      const service = new FinanceService(
        databaseFor(db),
        {} as AuditService,
        policy as unknown as CrmPolicy,
        {} as RealtimeBus,
      );
      const actor = { userId: "director-a", role: "director" as const };

      await expect(
        service.listStudentBalances(actor, {
          studentId: "00000000-0000-0000-0000-000000000201",
        }),
      ).resolves.toMatchObject({
        items: [{ totalPaid: 24000, totalCost: 3000, balance: 21000 }],
      });
      await expect(
        service.listStudentBalances(actor, {
          studentId: "00000000-0000-0000-0000-000000000202",
        }),
      ).resolves.toMatchObject({
        items: [{ totalPaid: 16000, totalCost: 1000, balance: 15000 }],
      });
      await expect(
        service.listStudentBalances(actor, {
          studentId: "00000000-0000-0000-0000-000000000203",
        }),
      ).resolves.toMatchObject({
        items: [{ totalPaid: 0, totalCost: 0, balance: 0 }],
      });
      await expect(
        service.listStudentBalances(actor, {
          studentId: "00000000-0000-0000-0000-000000000204",
        }),
      ).resolves.toMatchObject({
        items: [{ totalPaid: 0, totalCost: 1000, balance: -1000 }],
      });
      expect(policy.assertCanReadSchoolFinance).toHaveBeenCalledTimes(4);
    } finally {
      await db.close();
    }
  });
});
