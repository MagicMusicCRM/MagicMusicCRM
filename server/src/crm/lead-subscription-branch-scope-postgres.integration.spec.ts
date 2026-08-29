import { NotFoundException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { SubscriptionCommercialTermsService } from "./commerce/subscription-commercial-terms.service";
import { SubscriptionIssueRepository } from "./commerce/subscription-issue.repository";
import { SubscriptionPurchasePersistenceService } from "./commerce/subscription-purchase-persistence.service";
import { SubscriptionPurchasePreviewService } from "./commerce/subscription-purchase-preview.service";
import { SubscriptionPurchaseTermsService } from "./commerce/subscription-purchase-terms.service";
import { CrmPolicy } from "./crm.policy";
import { PurchaseSubscriptionCommandDto } from "./dto/issue-subscription.dto";
import { SubscriptionsService } from "./subscriptions.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Lead purchase scope tests require local PostgreSQL.");
}

const marker = `lead-purchase-scope-${randomUUID()}`;

jest.setTimeout(60_000);

describe("Lead subscription purchase branch scope (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let service: SubscriptionsService;
  let managerUserId: string;
  let managerProfileId: string;
  let managerStaffId: string;
  let assignedBranchId: string;
  let outsideBranchId: string;
  let outsideLeadId: string;
  let assignedLeadId: string;
  let outsideStudentId: string;
  let packageId: string;
  let previewWriter: jest.Mock;
  let purchaseWriter: jest.Mock;
  let integrityMutation: jest.Mock;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);

    const fixture = await createFixture(pool);
    managerUserId = fixture.managerUserId;
    managerProfileId = fixture.managerProfileId;
    managerStaffId = fixture.managerStaffId;
    assignedBranchId = fixture.assignedBranchId;
    outsideBranchId = fixture.outsideBranchId;
    outsideLeadId = fixture.outsideLeadId;
    assignedLeadId = fixture.assignedLeadId;
    outsideStudentId = fixture.outsideStudentId;
    packageId = randomUUID();

    previewWriter = jest.fn(() => {
      throw new Error("Out-of-scope Lead reached purchase preview writer.");
    });
    purchaseWriter = jest.fn(() => {
      throw new Error("Out-of-scope Lead reached purchase persistence writer.");
    });
    const purchasePreview = {
      previewFromContext: previewWriter,
      decodeBoundToken: jest.fn().mockReturnValue({
        issuedAtSeconds: Math.floor(Date.now() / 1_000),
      }),
    };
    integrityMutation = jest.fn(
      async (command: {
        mutate: (
          client: PoolClient,
          nextVersion: number,
        ) => Promise<Record<string, unknown>>;
      }) =>
        database.transaction(async (client) => ({
          resultRef: await command.mutate(client, 1),
          version: 1,
          replayed: false,
          auditId: "unused",
          eventId: "unused",
        })),
    );
    const integrity = {
      executeVersionedMutation: integrityMutation,
    };

    service = new SubscriptionsService(
      database,
      { record: jest.fn() } as unknown as AuditService,
      new CrmPolicy(),
      {
        emitCrmChanged: jest.fn(),
        emitFinanceChanged: jest.fn(),
      } as unknown as RealtimeBus,
      new SubscriptionIssueRepository(database),
      new SubscriptionCommercialTermsService(
        new SubscriptionPurchaseTermsService(),
      ),
      purchasePreview as unknown as SubscriptionPurchasePreviewService,
      integrity as unknown as PlatformIntegrityService,
      {
        persist: purchaseWriter,
      } as unknown as SubscriptionPurchasePersistenceService,
    );
  });

  afterAll(async () => {
    if (pool) {
      await cleanupFixture(pool, {
        outsideLeadId,
        assignedLeadId,
        outsideStudentId,
        managerStaffId,
        managerProfileId,
        managerUserId,
        branchIds: [assignedBranchId, outsideBranchId].filter(Boolean),
      });
    }
    if (database) await database.onModuleDestroy();
    if (pool) await pool.end();
  });

  beforeEach(() => {
    previewWriter.mockClear();
    purchaseWriter.mockClear();
  });

  it("hides an outside-branch Lead before purchase preview composition", async () => {
    await expect(
      service.previewLeadSubscriptionPurchase(
        managerActor(),
        outsideLeadId,
        purchaseDto(),
      ),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(previewWriter).not.toHaveBeenCalled();
    expect(purchaseWriter).not.toHaveBeenCalled();
  });

  it("hides an outside-branch Lead before the purchase persistence writer", async () => {
    await expect(
      service.issueLeadSubscription(
        managerActor(),
        outsideLeadId,
        purchaseDto(),
        {
          idempotencyKey: `${marker}-commit`,
          requestId: `${marker}-request`,
        },
      ),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(previewWriter).not.toHaveBeenCalled();
    expect(purchaseWriter).not.toHaveBeenCalled();
    await expect(noPurchaseFacts(pool, outsideLeadId)).resolves.toEqual({
      students: "0",
      subscriptions: "0",
    });
  });

  it("rechecks Lead scope before returning an idempotent replay", async () => {
    integrityMutation.mockResolvedValueOnce({
      resultRef: {
        entityId: randomUUID(),
        version: 1,
        studentId: randomUUID(),
        converted: false,
      },
      version: 1,
      replayed: true,
      auditId: "replay-audit",
      eventId: "replay-event",
    });

    await expect(
      service.issueLeadSubscription(
        managerActor(),
        outsideLeadId,
        purchaseDto(),
        {
          idempotencyKey: `${marker}-replay`,
          requestId: `${marker}-replay-request`,
        },
      ),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(previewWriter).not.toHaveBeenCalled();
    expect(purchaseWriter).not.toHaveBeenCalled();
    await expect(noPurchaseFacts(pool, outsideLeadId)).resolves.toEqual({
      students: "0",
      subscriptions: "0",
    });
  });

  it("rechecks the converted Student scope before returning a replay", async () => {
    integrityMutation.mockResolvedValueOnce({
      resultRef: {
        entityId: randomUUID(),
        version: 1,
        studentId: outsideStudentId,
        converted: false,
      },
      version: 1,
      replayed: true,
      auditId: "student-drift-audit",
      eventId: "student-drift-event",
    });

    await expect(
      service.issueLeadSubscription(
        managerActor(),
        assignedLeadId,
        purchaseDto(assignedLeadId),
        {
          idempotencyKey: `${marker}-student-drift`,
          requestId: `${marker}-student-drift-request`,
        },
      ),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(previewWriter).not.toHaveBeenCalled();
    expect(purchaseWriter).not.toHaveBeenCalled();
  });

  function managerActor() {
    return { userId: managerUserId, role: "manager" as const };
  }

  function purchaseDto(leadId = outsideLeadId): PurchaseSubscriptionCommandDto {
    return {
      packageId,
      payerStudentId: leadId,
      fundingMode: "personal_account",
      startsAt: "2026-08-01",
      expiresAt: "2026-09-01",
      paymentAmountMinor: "800000",
      paymentOccurredAt: "2026-08-01T09:00:00.000Z",
      paymentMethod: "cashless",
      previewToken: "scope-test-token",
      confirm: true,
    };
  }
});

async function createFixture(pool: Pool): Promise<{
  managerUserId: string;
  managerProfileId: string;
  managerStaffId: string;
  assignedBranchId: string;
  outsideBranchId: string;
  outsideLeadId: string;
  assignedLeadId: string;
  outsideStudentId: string;
}> {
  const client = await pool.connect();
  await client.query("begin");
  try {
    const manager = await client.query<{ id: string }>(
      `insert into app.users (email, role, email_verified_at)
       values ($1, 'manager', now()) returning id`,
      [`${marker}@example.test`],
    );
    const branches = await client.query<{ id: string }>(
      `insert into app.branches (name, timezone_name)
       values ($1, 'Europe/Moscow'), ($2, 'Europe/Moscow') returning id`,
      [`${marker}-assigned`, `${marker}-outside`],
    );
    const profile = await client.query<{ id: string }>(
      `insert into app.profiles (user_id, first_name, last_name)
       values ($1, 'Scope', 'Manager') returning id`,
      [manager.rows[0]!.id],
    );
    const staff = await client.query<{ id: string }>(
      `insert into app.staff_members (profile_id, role)
       values ($1, 'manager') returning id`,
      [profile.rows[0]!.id],
    );
    await client.query(
      `insert into app.staff_branch_assignments (staff_member_id, branch_id)
       values ($1, $2)`,
      [staff.rows[0]!.id, branches.rows[0]!.id],
    );
    const lead = await client.query<{ id: string }>(
      `insert into app.leads (
         first_name, last_name, custom_data, branch_id, created_by
       ) values ('Outside', 'Lead', '{}'::jsonb, $1, $2) returning id`,
      [branches.rows[1]!.id, manager.rows[0]!.id],
    );
    const assignedLead = await client.query<{ id: string }>(
      `insert into app.leads (
         first_name, last_name, custom_data, branch_id, created_by
       ) values ('Assigned', 'Lead', '{}'::jsonb, $1, $2) returning id`,
      [branches.rows[0]!.id, manager.rows[0]!.id],
    );
    const outsideStudent = await client.query<{ id: string }>(
      `insert into app.students (profile_id, status, branch_id)
       values ($1, 'active', $2) returning id`,
      [profile.rows[0]!.id, branches.rows[1]!.id],
    );
    await client.query("commit");
    return {
      managerUserId: manager.rows[0]!.id,
      managerProfileId: profile.rows[0]!.id,
      managerStaffId: staff.rows[0]!.id,
      assignedBranchId: branches.rows[0]!.id,
      outsideBranchId: branches.rows[1]!.id,
      outsideLeadId: lead.rows[0]!.id,
      assignedLeadId: assignedLead.rows[0]!.id,
      outsideStudentId: outsideStudent.rows[0]!.id,
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function cleanupFixture(
  pool: Pool,
  input: {
    outsideLeadId?: string;
    assignedLeadId?: string;
    outsideStudentId?: string;
    managerStaffId?: string;
    managerProfileId?: string;
    managerUserId?: string;
    branchIds: string[];
  },
): Promise<void> {
  const client = await pool.connect();
  await client.query("begin");
  try {
    if (input.outsideLeadId) {
      await client.query("delete from app.leads where id = $1", [
        input.outsideLeadId,
      ]);
    }
    if (input.assignedLeadId) {
      await client.query("delete from app.leads where id = $1", [
        input.assignedLeadId,
      ]);
    }
    if (input.outsideStudentId) {
      await client.query("delete from app.students where id = $1", [
        input.outsideStudentId,
      ]);
    }
    if (input.managerStaffId) {
      await client.query(
        "delete from app.staff_branch_assignments where staff_member_id = $1",
        [input.managerStaffId],
      );
      await client.query("delete from app.staff_members where id = $1", [
        input.managerStaffId,
      ]);
    }
    if (input.managerProfileId) {
      await client.query("delete from app.profiles where id = $1", [
        input.managerProfileId,
      ]);
    }
    if (input.managerUserId) {
      await client.query("delete from app.users where id = $1", [
        input.managerUserId,
      ]);
    }
    if (input.branchIds.length > 0) {
      await client.query(
        "delete from app.branches where id = any($1::uuid[])",
        [input.branchIds],
      );
    }
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function noPurchaseFacts(
  pool: Pool,
  leadId: string,
): Promise<{ students: string; subscriptions: string }> {
  const result = await pool.query<{ students: string; subscriptions: string }>(
    `select
       (select count(*)::text from app.students where lead_id = $1) as students,
       (select count(*)::text from app.subscriptions
          where conversion_lead_id = $1) as subscriptions`,
    [leadId],
  );
  return result.rows[0]!;
}
