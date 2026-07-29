import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { MigrationRunner } from "../../db/migration-runner";
import { CommerceSchemaRepository } from "./commerce-schema.repository";
import { IssuedCommercialSnapshot } from "./commerce-schema.types";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Commerce schema tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

async function expectRejectedFactMutation(
  client: PoolClient,
  work: () => Promise<unknown>,
) {
  const savepoint = `sp_${randomUUID().replace(/-/g, "")}`;
  await client.query(`savepoint ${savepoint}`);
  try {
    await work();
    throw new Error("Expected immutable commerce fact mutation to fail.");
  } catch (error) {
    expect((error as { code?: string }).code).toBe("23514");
    await client.query(`rollback to savepoint ${savepoint}`);
  } finally {
    await client.query(`release savepoint ${savepoint}`);
  }
}

describe("Commerce catalog/snapshot/ledger schema (PostgreSQL)", () => {
  let pool: Pool;
  let repository: CommerceSchemaRepository;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    repository = new CommerceSchemaRepository();
  });

  afterAll(async () => {
    await pool.end();
  });

  it("keeps issued snapshots stable while catalog versions change", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const fixture = await createClientFixture(client);
      const packageRow = await repository.createPackage(client, {
        name: "10 часов",
        unitCount: "10.00",
        validityDays: 90,
        basePriceMinor: "800000",
      });
      expect(packageRow).toMatchObject({
        basePriceMinor: "800000",
        currencyCode: "RUB",
        version: 1,
      });

      const percentSnapshot: IssuedCommercialSnapshot = {
        snapshotVersion: 1,
        packageVersion: packageRow.version,
        displayName: packageRow.name,
        unitCount: packageRow.unitCount,
        validityDays: packageRow.validityDays,
        basePriceMinor: packageRow.basePriceMinor,
        currencyCode: packageRow.currencyCode,
        discount: {
          type: "percent",
          percentBasisPoints: 2000,
          reason: "Скидка владельца",
        },
        finalPriceMinor: "640000",
        commercialRules: { writeOff: "hour" },
      };
      const issued = await repository.createIssuedSubscription(client, {
        studentId: fixture.studentId,
        packageId: packageRow.id,
        startsAt: "2026-07-29",
        expiresAt: "2026-10-27",
        snapshot: percentSnapshot,
      });
      expect(issued.commercialSnapshot).toEqual(percentSnapshot);

      const fixedSnapshot: IssuedCommercialSnapshot = {
        ...percentSnapshot,
        discount: {
          type: "fixed",
          fixedMinor: "160000",
          reason: "Фиксированная скидка",
        },
      };
      const fixedIssued = await repository.createIssuedSubscription(client, {
        studentId: fixture.studentId,
        packageId: packageRow.id,
        startsAt: "2026-07-29",
        expiresAt: "2026-10-27",
        snapshot: fixedSnapshot,
      });
      expect(fixedIssued.commercialSnapshot.discount).toEqual(
        fixedSnapshot.discount,
      );

      const updatedPackage = await repository.updatePackage(client, {
        id: packageRow.id,
        expectedVersion: 1,
        name: "10 часов — новая цена",
        basePriceMinor: "900000",
      });
      expect(updatedPackage).toMatchObject({
        name: "10 часов — новая цена",
        basePriceMinor: "900000",
        version: 2,
      });
      expect(
        await repository.findIssuedSubscription(client, issued.id),
      ).toEqual(issued);

      await client.query(
        `
          update app.subscriptions
          set lessons_used = 1, status = 'cancelled', version = version + 1
          where id = $1
        `,
        [issued.id],
      );
      await expectRejectedFactMutation(client, () =>
        client.query(
          `
            update app.subscriptions
            set final_price_minor = final_price_minor + 1
            where id = $1
          `,
          [issued.id],
        ),
      );
      await expectRejectedFactMutation(client, () =>
        client.query("delete from app.subscriptions where id = $1", [issued.id]),
      );
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("stores installments and rejects destructive payment/ledger/lesson fact writes", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const fixture = await createClientFixture(client, true);
      const packageRow = await repository.createPackage(client, {
        name: "Ledger fixture",
        unitCount: "8.00",
        basePriceMinor: "640000",
      });
      const snapshot: IssuedCommercialSnapshot = {
        snapshotVersion: 1,
        packageVersion: 1,
        displayName: packageRow.name,
        unitCount: packageRow.unitCount,
        validityDays: null,
        basePriceMinor: "640000",
        currencyCode: "RUB",
        discount: { type: "none" },
        finalPriceMinor: "640000",
        commercialRules: {},
      };
      const issued = await repository.createIssuedSubscription(client, {
        studentId: fixture.studentId,
        packageId: packageRow.id,
        startsAt: "2026-07-29",
        snapshot,
      });
      const firstInstallment = await repository.appendInstallment(client, {
        issuedSubscriptionId: issued.id,
        installmentNumber: 1,
        dueAt: new Date("2026-07-29T09:00:00Z"),
        amountMinor: "320000",
      });
      const secondInstallment = await repository.appendInstallment(client, {
        issuedSubscriptionId: issued.id,
        installmentNumber: 2,
        dueAt: new Date("2026-08-29T09:00:00Z"),
        amountMinor: "320000",
      });
      expect(
        BigInt(firstInstallment.amountMinor) +
          BigInt(secondInstallment.amountMinor),
      ).toBe(640000n);

      const payment = await repository.appendActualPayment(client, {
        studentId: fixture.studentId,
        issuedSubscriptionId: issued.id,
        amountMinor: "320000",
        method: "cashless",
        occurredAt: new Date("2026-07-29T10:00:00Z"),
        idempotencyRef: `payment:${randomUUID()}`,
        requestFingerprint: "sha256:test-payment",
        createdBy: fixture.managerId,
      });
      expect(payment).toMatchObject({
        amountMinor: "320000",
        currencyCode: "RUB",
        method: "cashless",
      });

      const obligation = await repository.appendObligationFact(client, {
        studentId: fixture.studentId,
        issuedSubscriptionId: issued.id,
        factType: "issue",
        direction: "debit",
        amountMinor: "640000",
        sourceType: "subscription.issue",
        sourceRef: issued.id,
      });
      const lifecycle = await repository.appendLifecycleEvent(client, {
        issuedSubscriptionId: issued.id,
        eventType: "issue",
        afterIssuedSubscriptionId: issued.id,
        actorUserId: fixture.managerId,
        reason: "Первичная выдача",
        aggregateVersion: 1,
      });

      await expectRejectedFactMutation(client, () =>
        client.query(
          "update app.payments set amount_minor = amount_minor + 1 where id = $1",
          [payment.id],
        ),
      );
      await expectRejectedFactMutation(client, () =>
        client.query("delete from app.payments where id = $1", [payment.id]),
      );
      await expectRejectedFactMutation(client, () =>
        client.query(
          `
            update app.subscription_obligation_facts
            set amount_minor = amount_minor + 1
            where id = $1
          `,
          [obligation.id],
        ),
      );
      await expectRejectedFactMutation(client, () =>
        client.query(
          "delete from app.subscription_lifecycle_events where id = $1",
          [lifecycle.id],
        ),
      );

      const lesson = await client.query<{ id: string }>(
        `
          insert into app.lessons (
            student_id,
            teacher_id,
            branch_id,
            scheduled_at,
            duration_minutes,
            status,
            created_by
          )
          values ($1, $2, $3, now() - interval '2 hours', 60, 'completed', $4)
          returning id
        `,
        [
          fixture.studentId,
          fixture.teacherId,
          fixture.branchId,
          fixture.managerId,
        ],
      );
      const lessonId = lesson.rows[0]!.id;
      await client.query(
        `
          insert into app.lesson_client_charge_facts (
            lesson_id,
            client_type,
            client_id,
            charge_type,
            snapshot_value,
            amount_minor,
            units
          )
          values ($1, 'student', $2, 'personal_account', 100, 10000, 0)
        `,
        [lessonId, fixture.studentId],
      );
      await client.query(
        `
          insert into app.lesson_teacher_compensation_facts (
            lesson_id,
            teacher_id,
            compensation_type,
            snapshot_rate,
            rate_minor,
            duration_minutes,
            amount_minor
          )
          values ($1, $2, 'fixed', 700, 70000, 60, 70000)
        `,
        [lessonId, fixture.teacherId],
      );
      await expectRejectedFactMutation(client, () =>
        client.query(
          `
            update app.lesson_client_charge_facts
            set amount_minor = amount_minor + 1
            where lesson_id = $1
          `,
          [lessonId],
        ),
      );
      await expectRejectedFactMutation(client, () =>
        client.query(
          "delete from app.lesson_teacher_compensation_facts where lesson_id = $1",
          [lessonId],
        ),
      );
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});

async function createClientFixture(
  client: PoolClient,
  withTeacher = false,
): Promise<{
  branchId: string;
  managerId: string;
  studentId: string;
  teacherId: string | null;
}> {
  const branch = await client.query<{ id: string }>(
    `
      insert into app.branches (name, timezone_name)
      values ($1, 'Europe/Moscow')
      returning id
    `,
    [`Commerce ${randomUUID()}`],
  );
  const branchId = branch.rows[0]!.id;
  const users = await client.query<{ id: string; role: string }>(
    `
      insert into app.users (email, role, email_verified_at)
      values
        ($1, 'manager', now()),
        ($2, 'client', now())
      returning id, role::text as role
    `,
    [
      `commerce-manager-${randomUUID()}@example.test`,
      `commerce-client-${randomUUID()}@example.test`,
    ],
  );
  const managerId = users.rows.find((row) => row.role === "manager")!.id;
  const clientUserId = users.rows.find((row) => row.role === "client")!.id;
  const studentProfile = await client.query<{ id: string }>(
    `
      insert into app.profiles (user_id, first_name, last_name)
      values ($1, 'Commerce', 'Client')
      returning id
    `,
    [clientUserId],
  );
  const student = await client.query<{ id: string }>(
    `
      insert into app.students (profile_id, branch_id)
      values ($1, $2)
      returning id
    `,
    [studentProfile.rows[0]!.id, branchId],
  );

  let teacherId: string | null = null;
  if (withTeacher) {
    const teacherUser = await client.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, 'teacher', now())
        returning id
      `,
      [`commerce-teacher-${randomUUID()}@example.test`],
    );
    const teacherProfile = await client.query<{ id: string }>(
      `
        insert into app.profiles (user_id, first_name, last_name)
        values ($1, 'Commerce', 'Teacher')
        returning id
      `,
      [teacherUser.rows[0]!.id],
    );
    const teacher = await client.query<{ id: string }>(
      `
        insert into app.teachers (profile_id)
        values ($1)
        returning id
      `,
      [teacherProfile.rows[0]!.id],
    );
    teacherId = teacher.rows[0]!.id;
  }
  return {
    branchId,
    managerId,
    studentId: student.rows[0]!.id,
    teacherId,
  };
}
