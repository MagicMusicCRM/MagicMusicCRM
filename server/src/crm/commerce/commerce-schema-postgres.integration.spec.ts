import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Pool, PoolClient } from "pg";
import { MigrationRunner } from "../../db/migration-runner";
import {
  backfillV7Commerce,
  reconcileV7Commerce,
} from "../../platform/v7-commerce-data";
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

  it("rolls surcharge terms down and up without schema drift", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const migrationRoot = resolve(process.cwd(), "db/migrations");
      await client.query(
        readFileSync(
          resolve(migrationRoot, "0095_subscription_surcharge_terms.down.sql"),
          "utf8",
        ),
      );
      expect(await hasColumn(client, "surcharge_minor")).toBe(false);

      await client.query(
        readFileSync(
          resolve(migrationRoot, "0095_subscription_surcharge_terms.up.sql"),
          "utf8",
        ),
      );
      expect(await hasColumn(client, "surcharge_minor")).toBe(true);
      expect(await hasColumn(client, "surcharge_reason")).toBe(true);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("deletes legacy subscriptions instead of leaving orphan rows", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const fixture = await createClientFixture(client);
      const subscription = await client.query<{ id: string }>(
        `
          insert into app.subscriptions (
            student_id, lessons_total, lessons_used, status
          ) values ($1, 10, 4, 'active')
          returning id
        `,
        [fixture.studentId],
      );

      const deleted = await client.query<{ id: string }>(
        "delete from app.subscriptions where id = $1 returning id",
        [subscription.rows[0]!.id],
      );
      expect(deleted.rows).toEqual(subscription.rows);
    } finally {
      await client.query("rollback");
      client.release();
    }
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

  it("moves legacy negative payment refunds into the adjustment ledger losslessly", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      await client.query(
        readFileSync(
          resolve(
            process.cwd(),
            "db/migrations/0116_v7_canonical_commerce_projections.down.sql",
          ),
          "utf8",
        ),
      );
      await client.query(`
        drop view app.commerce_ordinary_payments,
          app.commerce_ordinary_account_adjustments,
          app.commerce_ordinary_payment_records
      `);
      const fixture = await createClientFixture(client);
      await client.query("drop trigger if exists payments_immutable on app.payments");
      await client.query(
        "alter table app.payments drop constraint if exists payments_amount_minor_nonnegative",
      );
      const payment = await client.query<{ id: string }>(
        `
          insert into app.payments (
            student_id, amount, currency, payment_date, method, external_id,
            notes, created_by
          )
          values ($1, -4200, 'RUB', now(), 'cashless', $2, 'Возврат', $3)
          returning id
        `,
        [fixture.studentId, `legacy-refund-${randomUUID()}`, fixture.managerId],
      );
      const paymentId = payment.rows[0]!.id;
      const migration = readFileSync(
        resolve(
          process.cwd(),
          "db/migrations/0088z_legacy_negative_payment_refunds.up.sql",
        ),
        "utf8",
      );

      await client.query(migration);

      const remaining = await client.query(
        "select id from app.payments where id = $1",
        [paymentId],
      );
      const adjustment = await client.query<{
        id: string;
        amount: string;
        kind: string;
        externalId: string;
        currency: string;
      }>(
        `
          select id, amount::text, kind,
            legacy_payment_external_id as "externalId",
            legacy_payment_currency as currency
          from app.account_adjustments
          where id = $1
        `,
        [paymentId],
      );
      expect(remaining.rowCount).toBe(0);
      expect(adjustment.rows[0]).toMatchObject({
        id: paymentId,
        amount: "-4200.00",
        kind: "refund",
        currency: "RUB",
      });
      expect(adjustment.rows[0]!.externalId).toContain("legacy-refund-");

      const rollbackMigration = readFileSync(
        resolve(
          process.cwd(),
          "db/migrations/0088z_legacy_negative_payment_refunds.down.sql",
        ),
        "utf8",
      );
      await client.query(rollbackMigration);
      const restored = await client.query<{
        id: string;
        amount: string;
        externalId: string;
      }>(
        `
          select id, amount::text, external_id as "externalId"
          from app.payments
          where id = $1
        `,
        [paymentId],
      );
      const removedAdjustment = await client.query(
        "select id from app.account_adjustments where id = $1",
        [paymentId],
      );
      expect(restored.rows[0]).toMatchObject({
        id: paymentId,
        amount: "-4200.00",
      });
      expect(restored.rows[0]!.externalId).toContain("legacy-refund-");
      expect(removedAdjustment.rowCount).toBe(0);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("rolls the empty v7 commerce schema down and up losslessly", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const migrationRoot = resolve(process.cwd(), "db/migrations");
      await client.query(
        readFileSync(
          resolve(
            migrationRoot,
            "0116_v7_canonical_commerce_projections.down.sql",
          ),
          "utf8",
        ),
      );
      await client.query(`
        drop view app.commerce_ordinary_payments,
          app.commerce_ordinary_account_adjustments,
          app.commerce_ordinary_payment_records
      `);
      await client.query(
        readFileSync(
          resolve(migrationRoot, "0103_v7_client_commerce.down.sql"),
          "utf8",
        ),
      );
      expect(await hasColumn(client, "payer_student_id")).toBe(false);
      expect(
        (await client.query("select to_regclass('app.client_payment_records') as value"))
          .rows[0]?.value,
      ).toBeNull();

      await client.query(
        readFileSync(
          resolve(migrationRoot, "0103_v7_client_commerce.up.sql"),
          "utf8",
        ),
      );
      expect(await hasColumn(client, "payer_student_id")).toBe(true);
      const capabilities = await client.query<{ capability_key: string }>(
        `
          select capability_key
          from app.capability_definitions
          where active
            and capability_key in (
              'commerce.client_finance.write', 'config.commerce.manage'
            )
          order by capability_key
        `,
      );
      expect(capabilities.rows.map((row) => row.capability_key)).toEqual([
        "commerce.client_finance.write",
        "config.commerce.manage",
      ]);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("rolls the empty payment reversal boundary down and up losslessly", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const migrationRoot = resolve(process.cwd(), "db/migrations");
      await client.query(
        readFileSync(
          resolve(
            migrationRoot,
            "0116_v7_canonical_commerce_projections.down.sql",
          ),
          "utf8",
        ),
      );
      await client.query(
        readFileSync(
          resolve(migrationRoot, "0107_v7_payment_reversal.down.sql"),
          "utf8",
        ),
      );
      expect(
        (
          await client.query(
            "select to_regclass('app.commerce_ordinary_payments') as value",
          )
        ).rows[0]?.value,
      ).toBeNull();

      await client.query(
        readFileSync(
          resolve(migrationRoot, "0107_v7_payment_reversal.up.sql"),
          "utf8",
        ),
      );
      await client.query(
        readFileSync(
          resolve(
            migrationRoot,
            "0116_v7_canonical_commerce_projections.up.sql",
          ),
          "utf8",
        ),
      );
      expect(
        (
          await client.query(
            "select to_regclass('app.commerce_ordinary_payments') as value",
          )
        ).rows[0]?.value,
      ).toBe("app.commerce_ordinary_payments");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("rolls the empty human audit reason column down and up losslessly", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const migrationRoot = resolve(process.cwd(), "db/migrations");
      await client.query("update app.audit_events set reason_text = null");
      await client.query(
        readFileSync(
          resolve(migrationRoot, "0108_v7_client_finance_audit.down.sql"),
          "utf8",
        ),
      );
      const removed = await client.query<{ present: boolean }>(`
        select exists (
          select 1 from information_schema.columns
          where table_schema = 'app'
            and table_name = 'audit_events'
            and column_name = 'reason_text'
        ) as present
      `);
      expect(removed.rows[0]!.present).toBe(false);

      await client.query(
        readFileSync(
          resolve(migrationRoot, "0108_v7_client_finance_audit.up.sql"),
          "utf8",
        ),
      );
      const restored = await client.query<{ present: boolean }>(`
        select exists (
          select 1 from information_schema.columns
          where table_schema = 'app'
            and table_name = 'audit_events'
            and column_name = 'reason_text'
        ) as present
      `);
      expect(restored.rows[0]!.present).toBe(true);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("enforces payment state, identity and role-package constraints", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const fixture = await createClientFixture(client);
      await expectRejectedFactMutation(client, () =>
        client.query(
          `
            insert into app.client_payment_records (
              student_id, amount_minor, currency_code, status
            ) values ($1, 10000, 'RUB', 'paid')
          `,
          [fixture.studentId],
        ),
      );
      const payment = await client.query<{ id: string }>(
        `
          insert into app.client_payment_records (
            student_id, amount_minor, currency_code, status,
            due_at, verification_note, created_by
          ) values (
            $1, 10000, 'RUB', 'posted_pending', now(),
            'Проверить оплату за рассрочку', $2
          )
          returning id
        `,
        [fixture.studentId, fixture.managerId],
      );
      await expectRejectedFactMutation(client, () =>
        client.query(
          "update app.client_payment_records set amount_minor = 20000 where id = $1",
          [payment.rows[0]!.id],
        ),
      );

      const roleMatrix = await client.query<{
        capability_key: string;
        role: string;
        effect: string;
      }>(
        `
          select entry.capability_key, package.role::text, entry.effect
          from app.role_package_capabilities entry
          join app.role_packages package on package.id = entry.package_id
          where package.active
            and entry.capability_key in (
              'commerce.client_finance.write', 'config.commerce.manage'
            )
          order by entry.capability_key, package.role::text
        `,
      );
      expect(
        roleMatrix.rows.filter(
          (row) =>
            row.capability_key === "commerce.client_finance.write" &&
            row.effect === "allow",
        ).map((row) => row.role),
      ).toEqual(["admin", "director", "manager", "system_admin"]);
      expect(
        roleMatrix.rows.filter(
          (row) =>
            row.capability_key === "config.commerce.manage" &&
            row.effect === "allow",
        ).map((row) => row.role),
      ).toEqual(["director", "system_admin"]);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("backfills legacy payer/payment facts exactly once and detects version drift", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const fixture = await createClientFixture(client);
      const subscription = await client.query<{ id: string }>(
        `
          insert into app.subscriptions (
            student_id, lessons_total, lessons_used, status
          ) values ($1, 12, 0, 'active') returning id
        `,
        [fixture.studentId],
      );
      const payment = await client.query<{ id: string }>(
        `
          insert into app.payments (
            student_id, amount_minor, currency, method, payment_date,
            issued_subscription_id, external_id, created_by
          ) values (
            $1, 3000000, 'RUB', 'cashless',
            '2026-08-07T10:00:00Z', $2, $3, $4
          ) returning id
        `,
        [
          fixture.studentId,
          subscription.rows[0]!.id,
          `v7-backfill-${randomUUID()}`,
          fixture.managerId,
        ],
      );

      expect(await backfillV7Commerce(client)).toEqual({
        subscriptionsBackfilled: 1,
        paymentsBackfilled: 1,
        reviewRows: 0,
      });
      expect(await backfillV7Commerce(client)).toEqual({
        subscriptionsBackfilled: 0,
        paymentsBackfilled: 0,
        reviewRows: 0,
      });
      expect(await reconcileV7Commerce(client)).toEqual([]);

      const record = await client.query<{
        id: string;
        amount_minor: string;
        status: string;
        funding_mode: string;
        payer_student_id: string;
      }>(
        `
          select record.id, record.amount_minor, record.status,
                 subscription.funding_mode, subscription.payer_student_id
          from app.client_payment_records record
          join app.subscriptions subscription
            on subscription.id = record.issued_subscription_id
          where record.actual_payment_id = $1
        `,
        [payment.rows[0]!.id],
      );
      expect(record.rows[0]).toMatchObject({
        id: payment.rows[0]!.id,
        amount_minor: "3000000",
        status: "paid",
        funding_mode: "legacy",
        payer_student_id: fixture.studentId,
      });

      await client.query(
        `
          update app.aggregate_versions set version = 99
          where aggregate_type = 'commerce:client-payment'
            and aggregate_id = $1
        `,
        [record.rows[0]!.id],
      );
      expect(await reconcileV7Commerce(client)).toEqual([
        expect.objectContaining({
          issueCode: "payment.event_version_mismatch",
          entityId: record.rows[0]!.id,
        }),
      ]);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});

async function hasColumn(
  client: PoolClient,
  columnName: string,
): Promise<boolean> {
  const result = await client.query<{ present: boolean }>(
    `
      select exists (
        select 1
        from information_schema.columns
        where table_schema = 'app'
          and table_name = 'subscriptions'
          and column_name = $1
      ) as present
    `,
    [columnName],
  );
  return result.rows[0]?.present === true;
}

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
