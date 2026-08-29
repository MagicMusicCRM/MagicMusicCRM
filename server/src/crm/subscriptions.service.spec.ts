import {
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { CrmPolicy } from "./crm.policy";
import { SubscriptionsService } from "./subscriptions.service";
import { SubscriptionCommercialTermsService } from "./commerce/subscription-commercial-terms.service";
import { SubscriptionIssueRepository } from "./commerce/subscription-issue.repository";
import { SubscriptionPurchasePreviewService } from "./commerce/subscription-purchase-preview.service";
import { PaymentLifecycleRepository } from "./commerce/payment-lifecycle.repository";
import { SubscriptionPurchasePaymentService } from "./commerce/subscription-purchase-payment.service";
import { SubscriptionPurchasePersistenceService } from "./commerce/subscription-purchase-persistence.service";
import { SubscriptionPurchaseTermsService } from "./commerce/subscription-purchase-terms.service";

const purchaseDto = (packageId = "pkg-a") => ({
  packageId,
  payerStudentId: "lead-a",
  fundingMode: "personal_account" as const,
  startsAt: "2026-07-18",
  expiresAt: "2026-08-18",
  paymentAmountMinor: "800000",
  paymentOccurredAt: "2026-07-18T10:00:00.000Z",
  paymentMethod: "cashless" as const,
  previewToken: "signed-preview",
  confirm: true as const,
});

const metadata = {
  idempotencyKey: "lead-purchase-test",
  requestId: "lead-purchase-request",
};

const packageRow = {
  id: "pkg-a",
  name: "8 занятий",
  branch_id: "branch-a",
  lessons_total: "8",
  base_price_minor: "800000",
  currency_code: "RUB",
  validity_days: 30,
  version: 1,
};

function createIssueRepositoryMock() {
  return {
    findActivePackageForShare: jest.fn().mockResolvedValue(packageRow),
    lockPurchaseStudents: jest.fn().mockResolvedValue([]),
    readAccountBalance: jest.fn().mockResolvedValue("0"),
    createIssuedSubscription: jest
      .fn()
      .mockImplementation(async (_client, input) => ({
        id: "subscription-a",
        student_id: input.studentId,
        payer_student_id: input.payerStudentId,
        funding_mode: input.fundingMode,
        purchase_reason: input.purchaseReason,
        package_id: input.package.id,
        lessons_total: input.package.lessons_total,
        lessons_used: "0",
        starts_at: input.startsAt,
        expires_at: input.expiresAt,
        status: "active",
        version: 1,
        commercial_snapshot: input.snapshot,
        created_at: "2026-07-18T10:00:00.000Z",
      })),
    createActualPayment: jest.fn().mockResolvedValue({
      id: "payment-a",
      student_id: "student-a",
      issued_subscription_id: "subscription-a",
      amount_minor: "800000",
      currency: "RUB",
      method: "cashless",
      payment_date: "2026-07-18T10:00:00.000Z",
      branch_id: "branch-a",
      branch_name: null,
      notes: "Оплата при продаже",
      invoice_number: null,
      created_by: "manager-a",
      created_by_name: null,
      created_at: "2026-07-18T10:00:00.000Z",
    }),
    createInstallments: jest.fn().mockResolvedValue([]),
    createObligations: jest.fn().mockResolvedValue([]),
    createIssueLifecycle: jest.fn().mockResolvedValue(undefined),
  };
}

function createPurchasePreviewMock() {
  return {
    decodeBoundToken: jest
      .fn()
      .mockReturnValue({ issuedAtSeconds: Math.floor(Date.now() / 1_000) }),
    assertPurchaseContext: jest.fn().mockImplementation((context) => {
      if (!context.package) throw new Error("package missing");
      return context.package;
    }),
    createTokenPayload: jest.fn().mockReturnValue({}),
    assertStillCurrent: jest.fn(),
    previewFromContext: jest
      .fn()
      .mockReturnValue({ previewToken: "signed-preview" }),
  };
}

function createPaymentLifecycleMock() {
  return {
    createRecord: jest.fn().mockResolvedValue({
      id: "payment-record-a",
      status: "paid",
    }),
    linkActualPayment: jest.fn().mockResolvedValue(undefined),
    appendStatusEvent: jest.fn().mockResolvedValue(undefined),
    initializeRecordAggregate: jest.fn().mockResolvedValue(undefined),
  };
}

describe("SubscriptionsService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };
  const schoolActor = { userId: "director-a", role: "director" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const transaction = jest.fn(
      async (work: (client: { query: typeof query }) => Promise<unknown>) =>
        work({ query }),
    );
    const database = { query, transaction };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertCanManageSubscriptionPackages: jest.fn(),
      assertCanReadSchoolFinance: jest.fn(),
    };
    const realtime = {
      emitCrmChanged: jest.fn(),
      emitFinanceChanged: jest.fn(),
    };
    const issueRepository = createIssueRepositoryMock();
    const purchasePreview = createPurchasePreviewMock();
    const paymentLifecycle = createPaymentLifecycleMock();
    const purchasePersistence = new SubscriptionPurchasePersistenceService(
      issueRepository as unknown as SubscriptionIssueRepository,
      new SubscriptionPurchasePaymentService(
        issueRepository as unknown as SubscriptionIssueRepository,
        paymentLifecycle as unknown as PaymentLifecycleRepository,
      ),
    );
    const integrity = {
      executeVersionedMutation: jest.fn(async (command) => {
        const resultRef = await command.mutate({ query }, 1);
        return {
          resultRef,
          version: 1,
          replayed: false,
          auditId: "audit-a",
          eventId: "event-a",
        };
      }),
    };

    const service = new SubscriptionsService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      realtime as unknown as RealtimeBus,
      issueRepository as unknown as SubscriptionIssueRepository,
      new SubscriptionCommercialTermsService(
        new SubscriptionPurchaseTermsService(),
      ),
      purchasePreview as unknown as SubscriptionPurchasePreviewService,
      integrity as unknown as PlatformIntegrityService,
      purchasePersistence,
    );

    return {
      service,
      query,
      transaction,
      audit,
      policy,
      realtime,
      issueRepository,
      purchasePreview,
      paymentLifecycle,
      integrity,
    };
  };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const queued = [...results];
    const query = jest
      .fn()
      .mockImplementation(() =>
        Promise.resolve(queued.shift() ?? { rows: [] }),
      );
    const transaction = jest.fn(
      async (work: (client: { query: typeof query }) => Promise<unknown>) =>
        work({ query }),
    );
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertCanManageSubscriptionPackages: jest.fn(),
      assertCanReadSchoolFinance: jest.fn(),
    };
    const realtime = {
      emitCrmChanged: jest.fn(),
      emitFinanceChanged: jest.fn(),
    };
    const issueRepository = createIssueRepositoryMock();
    const purchasePreview = createPurchasePreviewMock();
    const paymentLifecycle = createPaymentLifecycleMock();
    const purchasePersistence = new SubscriptionPurchasePersistenceService(
      issueRepository as unknown as SubscriptionIssueRepository,
      new SubscriptionPurchasePaymentService(
        issueRepository as unknown as SubscriptionIssueRepository,
        paymentLifecycle as unknown as PaymentLifecycleRepository,
      ),
    );
    const integrity = {
      executeVersionedMutation: jest.fn(async (command) => {
        const resultRef = await command.mutate({ query }, 1);
        return {
          resultRef,
          version: 1,
          replayed: false,
          auditId: "audit-a",
          eventId: "event-a",
        };
      }),
    };
    const service = new SubscriptionsService(
      { query, transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      realtime as unknown as RealtimeBus,
      issueRepository as unknown as SubscriptionIssueRepository,
      new SubscriptionCommercialTermsService(
        new SubscriptionPurchaseTermsService(),
      ),
      purchasePreview as unknown as SubscriptionPurchasePreviewService,
      integrity as unknown as PlatformIntegrityService,
      purchasePersistence,
    );
    return {
      service,
      query,
      transaction,
      audit,
      policy,
      realtime,
      issueRepository,
      purchasePreview,
      paymentLifecycle,
      integrity,
    };
  };

  it("lists subscriptions with actor-scoped query and safe DTO", async () => {
    const { service, query } = createService([
      {
        id: "sub-a",
        student_id: "student-a",
        student_user_id: "client-a",
        lessons_total: 8,
        lessons_used: 3,
        starts_at: "2026-06-01",
        expires_at: "2026-07-01",
        status: "active",
        created_at: "2026-06-01T00:00:00.000Z",
        updated_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listSubscriptions(schoolActor, {
        studentId: "student-a",
        limit: 1,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: "sub-a",
          studentId: "student-a",
          lessonsTotal: 8,
          lessonsUsed: 3,
          startsAt: "2026-06-01",
          expiresAt: "2026-07-01",
          status: "active",
          createdAt: "2026-06-01T00:00:00.000Z",
          updatedAt: "2026-06-12T00:00:00.000Z",
          packageName: null,
          packagePrice: null,
          // Прихода нет — «Оплачено» неизвестно. Это НЕ «оплачено 0».
          paidAmount: null,
        },
      ],
    });

    expect(query.mock.calls[0][1]).toEqual([
      "director",
      "director-a",
      "student-a",
      1,
    ]);
  });

  it("denies teacher global subscriptions before composing finance rows", async () => {
    const { service, query, policy } = createService([]);
    policy.assertCanReadSchoolFinance.mockImplementation(() => {
      throw new ForbiddenException();
    });

    await expect(
      service.listSubscriptions(
        { userId: "teacher-a", role: "teacher" },
        { studentId: "student-linked", limit: 1 },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(query).not.toHaveBeenCalled();
  });

  it("issues a subscription from a package atomically with audit (P5b)", async () => {
    const { service, query, transaction, audit, policy, realtime } =
      createServiceWithQueryResults([
        { rows: [{ id: "student-a" }] },
        {
          rows: [
            {
              id: "sub-a",
              lessons_total: 8,
              lessons_used: 0,
              starts_at: "2026-06-22",
              expires_at: "2026-08-21",
              status: "active",
              package_id: "pkg-a",
              payment_id: "pay-a",
            },
          ],
        },
        { rows: [{ user_id: "client-a" }] }, // active Client finance audience
      ]);

    await expect(
      service.issueSubscription(actor, "student-a", { packageId: "pkg-a" }),
    ).resolves.toEqual({
      id: "sub-a",
      studentId: "student-a",
      lessonsTotal: 8,
      lessonsUsed: 0,
      startsAt: "2026-06-22",
      expiresAt: "2026-08-21",
      status: "active",
      packageId: "pkg-a",
      paymentId: "pay-a",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(transaction).toHaveBeenCalledTimes(1);
    const sql = String(query.mock.calls[1][0]);
    expect(sql).toContain("insert into app.payments");
    expect(sql).toContain("insert into app.subscriptions");
    expect(query.mock.calls[1][1]).toEqual(["student-a", "pkg-a", "manager-a"]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.subscription_issued",
        entityType: "student",
        entityId: "student-a",
      }),
    );
    expect(realtime.emitFinanceChanged).toHaveBeenCalledWith(["client-a"]);
    const financeAudienceSql = String(query.mock.calls[2][0]);
    expect(financeAudienceSql).toContain("recipient.role = 'client'");
    expect(financeAudienceSql).toContain("recipient.is_app_account = true");
  });

  it("atomically converts a lead only when issuing its subscription", async () => {
    const {
      service,
      query,
      audit,
      policy,
      realtime,
      issueRepository,
      paymentLifecycle,
      integrity,
    } = createServiceWithQueryResults([
      { rows: [] }, // advisory lock
      {
        rows: [
          {
            id: "lead-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: "+79990000000",
            custom_data: { discipline: "Фортепиано" },
            branch_id: "branch-a",
            source_id: "source-a",
            created_at: "2026-07-18T09:00:00.000Z",
            version: 1,
          },
        ],
      },
      {
        rows: [
          {
            id: "pkg-a",
            name: "8 занятий",
            discipline_id: "discipline-a",
            branch_id: "branch-a",
            lessons_total: "8",
            price: "8000.00",
            base_price_minor: "800000",
            currency_code: "RUB",
            version: "1",
            validity_days: 60,
            is_active: true,
            sort_order: 0,
            created_at: "2026-07-01T00:00:00.000Z",
          },
        ],
      },
      {
        rows: [
          {
            id: "lead-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: "+79990000000",
            custom_data: { discipline: "Фортепиано" },
            branch_id: "branch-a",
            source_id: "source-a",
            created_at: "2026-07-18T09:00:00.000Z",
            version: 1,
          },
        ],
      }, // signed preview context
      { rows: [] }, // no existing student
      { rows: [{ profile_id: "profile-client" }] },
      { rows: [{ id: "student-a" }] },
      { rows: [] }, // conversion link
      { rows: [] }, // copy user_crm_link
      { rows: [] }, // rebind administration chat
      { rows: [] }, // copy family membership
      { rows: [] }, // retire lead family membership
      {
        rows: [
          {
            id: "trial-a",
            student_id: "student-a",
            group_id: null,
            lead_id: null,
            teacher_id: "teacher-a",
          },
        ],
      }, // rebind trial
      { rows: [{ id: "hw-trial" }] }, // rebind homework
      {
        rows: [
          {
            id: "student-a",
            lead_id: "lead-a",
            status: "active",
            custom_data: {
              discipline: "Фортепиано",
              sourceLeadId: "lead-a",
            },
            profile_id: "profile-client",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: "+79990000000",
            created_at: "2026-07-18T10:00:00.000Z",
          },
        ],
      },
      { rows: [{ user_id: "client-a" }] }, // student realtime audience
      {
        rows: [{ user_id: "client-a" }, { user_id: "teacher-user" }],
      }, // converted lesson audience
      {
        rows: [{ user_id: "client-a" }, { user_id: "teacher-user" }],
      }, // converted homework audience
      {
        rows: [{ user_id: "client-a" }],
      }, // finance audience: active Client accounts only
    ]);

    await expect(
      service.issueLeadSubscription(actor, "lead-a", purchaseDto(), metadata),
    ).resolves.toEqual({
      student: expect.objectContaining({ id: "student-a", leadId: "lead-a" }),
      subscription: expect.objectContaining({
        id: "subscription-a",
        packageId: "pkg-a",
        paymentId: "payment-a",
      }),
      payment: expect.objectContaining({ id: "payment-a", amount: 8000 }),
      converted: true,
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("pg_advisory_xact_lock"),
      ),
    ).toBe(true);
    const leadScopeQueries = query.mock.calls.filter((call) =>
      String(call[0]).includes("from app.leads lead"),
    );
    expect(leadScopeQueries).toHaveLength(2);
    for (const call of leadScopeQueries) {
      expect(String(call[0])).toContain("app.staff_branch_assignments");
      expect(call[1]).toEqual(["lead-a", "manager-a"]);
    }
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes(
          "set student_id = $2, lead_id = null, updated_at = now()",
        ),
      ),
    ).toBe(true);
    const chatRebind = query.mock.calls.find((call) =>
      String(call[0]).includes("update app.chats chat"),
    );
    expect(chatRebind).toBeDefined();
    expect(chatRebind?.[1]).toEqual(["lead-a", "student-a"]);
    const chatRebindSql = String(chatRebind?.[0]);
    expect(chatRebindSql).toContain("chat.lead_id = $1");
    expect(chatRebindSql).toContain("chat.type = 'administration'");
    expect(chatRebindSql).toContain("link.user_id = chat.owner_user_id");
    expect(chatRebindSql).toContain("link.entity_type = 'lead'");
    expect(chatRebindSql).toContain("link.entity_id = $1");
    expect(chatRebindSql).toContain(
      "chat.slug is distinct from 'announcements'",
    );
    expect(issueRepository.createIssuedSubscription).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        studentId: "student-a",
        payerStudentId: "student-a",
        startsAt: "2026-07-18",
        expiresAt: "2026-08-18",
        conversionLeadId: "lead-a",
      }),
    );
    expect(issueRepository.createActualPayment).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        studentId: "student-a",
        amountMinor: "800000",
        method: "cashless",
      }),
    );
    expect(issueRepository.createObligations).toHaveBeenCalledTimes(1);
    expect(paymentLifecycle.createRecord).toHaveBeenCalledTimes(1);
    expect(paymentLifecycle.linkActualPayment).toHaveBeenCalledTimes(1);
    expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: "crm.lead-subscription.purchase",
        aggregateType: "commerce:issued-subscription",
        expectedVersion: 0,
        idempotencyKey: metadata.idempotencyKey,
        payload: {
          leadId: "lead-a",
          legacyLeadAutoPayment: false,
          commandFingerprint: expect.stringMatching(/^[a-f0-9]{64}$/),
        },
        audit: expect.objectContaining({
          action: "crm.subscription_purchased",
        }),
        outbox: expect.objectContaining({
          type: "commerce.subscription.changed",
        }),
      }),
    );
    expect(
      JSON.stringify(
        integrity.executeVersionedMutation.mock.calls[0][0].payload,
      ),
    ).not.toContain("signed-preview");
    expect(String(query.mock.calls[6][0])).toContain("updated_profile as");
    const linkedProfileParams = query.mock.calls[6][1] as unknown[];
    expect(linkedProfileParams[0]).toBe("profile-client");
    expect(linkedProfileParams[3]).toBe("+79990000000");
    expect(linkedProfileParams[4]).toBe("lead-a");
    expect(JSON.parse(String(linkedProfileParams[5]))).toMatchObject({
      sourceLeadId: "lead-a",
      sourceLeadEmail: "anna@example.com",
      appealAt: "2026-07-18T09:00:00.000Z",
    });
    expect(linkedProfileParams[6]).toBe("branch-a");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.student_created",
        metadata: { leadId: "lead-a", trigger: "subscription" },
      }),
    );
    expect(audit.record).toHaveBeenCalledTimes(1);
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith(
      expect.objectContaining({
        entity: "lesson",
        id: "trial-a",
        affectedUserIds: ["client-a", "teacher-user"],
      }),
    );
    expect(realtime.emitFinanceChanged).toHaveBeenCalledWith(["client-a"]);
    expect(realtime.emitFinanceChanged).not.toHaveBeenCalledWith(
      expect.arrayContaining(["teacher-user"]),
    );
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith(
      expect.objectContaining({
        entity: "homework",
        id: "hw-trial",
        affectedUserIds: ["client-a", "teacher-user"],
      }),
    );
  });

  it("keeps generic issuance available for legacy students linked to leads", async () => {
    const { service, query, transaction, audit } =
      createServiceWithQueryResults([
        {
          // Imported students commonly retain lead_id but predate the durable
          // conversion marker introduced by migration 0072.
          rows: [{ id: "student-a", lead_id: "lead-a" }],
        },
        {
          rows: [
            {
              id: "sub-a",
              lessons_total: 8,
              lessons_used: 0,
              starts_at: "2026-07-18",
              expires_at: "2026-09-16",
              status: "active",
              package_id: "pkg-a",
              payment_id: "pay-a",
            },
          ],
        },
        { rows: [] },
      ]);

    await expect(
      service.issueSubscription(actor, "student-a", { packageId: "pkg-a" }),
    ).resolves.toEqual(
      expect.objectContaining({
        id: "sub-a",
        studentId: "student-a",
        packageId: "pkg-a",
        paymentId: "pay-a",
      }),
    );
    expect(transaction).toHaveBeenCalledTimes(1);
    expect(String(query.mock.calls[0][0])).toContain("select student.id");
    expect(String(query.mock.calls[0][0])).not.toContain("conversion_lead_id");
    expect(String(query.mock.calls[1][0])).toContain(
      "insert into app.payments",
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.subscription_issued",
        entityId: "student-a",
        metadata: expect.objectContaining({ subscriptionId: "sub-a" }),
      }),
    );
  });

  it("replays canonical idempotency and propagates conflicting key reuse", async () => {
    const existing = {
      id: "student-a",
      lead_id: "lead-a",
      status: "active",
      custom_data: {},
      profile_id: "profile-a",
      profile_user_id: "client-a",
      first_name: "Анна",
      last_name: "Иванова",
      email: "anna@example.com",
      phone: null,
      created_at: "2026-07-18T10:00:00.000Z",
      subscription_id: "subscription-a",
      lessons_total: "8",
      lessons_used: "0",
      starts_at: "2026-07-18",
      expires_at: null,
      subscription_status: "active",
      package_id: "pkg-a",
      payment_id: "payment-a",
      payment_amount: "800000",
      payment_currency: "RUB",
      payment_date: "2026-07-18T10:00:00.000Z",
      payment_method: null,
      payment_notes: "Покупка абонемента",
    };
    const retry = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lead-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            custom_data: {},
            branch_id: "branch-a",
            source_id: "source-a",
            created_at: "2026-07-18T09:00:00.000Z",
            version: 1,
          },
        ],
      },
      { rows: [existing] },
    ]);
    retry.integrity.executeVersionedMutation.mockResolvedValueOnce({
      resultRef: {
        entityId: "subscription-a",
        version: 1,
        studentId: "student-a",
        converted: false,
      },
      version: 1,
      replayed: true,
      auditId: "audit-a",
      eventId: "event-a",
    });
    retry.issueRepository.lockPurchaseStudents.mockResolvedValueOnce([
      { id: "student-a", version: 1, branch_id: "branch-a" },
    ]);

    await expect(
      retry.service.issueLeadSubscription(
        actor,
        "lead-a",
        purchaseDto(),
        metadata,
      ),
    ).resolves.toMatchObject({
      subscription: { id: "subscription-a" },
      payment: { id: "payment-a", amount: 8000 },
      converted: false,
    });
    expect(retry.audit.record).not.toHaveBeenCalled();
    expect(
      retry.query.mock.calls.some((call) =>
        String(call[0]).includes("insert into app.payments"),
      ),
    ).toBe(false);

    const revoked = createServiceWithQueryResults([{ rows: [] }]);
    revoked.integrity.executeVersionedMutation.mockResolvedValueOnce({
      resultRef: {
        entityId: "subscription-a",
        version: 1,
        studentId: "student-a",
        converted: false,
      },
      version: 1,
      replayed: true,
      auditId: "audit-a",
      eventId: "event-a",
    });
    await expect(
      revoked.service.issueLeadSubscription(
        actor,
        "lead-a",
        purchaseDto(),
        metadata,
      ),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(
      revoked.query.mock.calls.some((call) =>
        String(call[0]).includes("from app.subscriptions subscription"),
      ),
    ).toBe(false);

    const driftedStudent = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lead-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            custom_data: {},
            branch_id: "branch-a",
            source_id: "source-a",
            created_at: "2026-07-18T09:00:00.000Z",
            version: 1,
          },
        ],
      },
    ]);
    driftedStudent.integrity.executeVersionedMutation.mockResolvedValueOnce({
      resultRef: {
        entityId: "subscription-a",
        version: 1,
        studentId: "student-a",
        converted: false,
      },
      version: 1,
      replayed: true,
      auditId: "audit-a",
      eventId: "event-a",
    });
    driftedStudent.issueRepository.lockPurchaseStudents.mockResolvedValueOnce(
      [],
    );
    await expect(
      driftedStudent.service.issueLeadSubscription(
        actor,
        "lead-a",
        purchaseDto(),
        metadata,
      ),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(
      driftedStudent.query.mock.calls.some((call) =>
        String(call[0]).includes("from app.subscriptions subscription"),
      ),
    ).toBe(false);

    const mismatch = createServiceWithQueryResults([]);
    mismatch.integrity.executeVersionedMutation.mockRejectedValueOnce(
      new ConflictException(),
    );
    await expect(
      mismatch.service.issueLeadSubscription(
        actor,
        "lead-a",
        purchaseDto("pkg-other"),
        metadata,
      ),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("keeps lead subscription conversion behind the CRM write actor matrix", async () => {
    const { service, policy, transaction } = createServiceWithQueryResults([]);
    policy.assertCanWriteCrm.mockImplementation((candidate) => {
      if (candidate.role === "client" || candidate.role === "teacher") {
        throw new ForbiddenException();
      }
    });

    await expect(
      service.issueLeadSubscription(
        { userId: "client-a", role: "client" },
        "lead-a",
        purchaseDto(),
        metadata,
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await expect(
      service.issueLeadSubscription(
        { userId: "teacher-a", role: "teacher" },
        "lead-a",
        purchaseDto(),
        metadata,
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(transaction).not.toHaveBeenCalled();
  });

  it("fails closed when a manager previews a lead outside assigned branches", async () => {
    const { service, query, purchasePreview } = createServiceWithQueryResults([
      { rows: [] },
    ]);

    await expect(
      service.previewLeadSubscriptionPurchase(actor, "lead-a", purchaseDto()),
    ).rejects.toBeInstanceOf(NotFoundException);

    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("from app.leads lead");
    expect(sql).toContain("app.staff_branch_assignments");
    expect(query.mock.calls[0][1]).toEqual(["lead-a", "manager-a"]);
    expect(purchasePreview.previewFromContext).not.toHaveBeenCalled();
  });

  it.each(["director", "system_admin"] as const)(
    "keeps %s lead purchase scope unrestricted",
    async (role) => {
      const { service, query } = createServiceWithQueryResults([
        {
          rows: [
            {
              id: "lead-a",
              first_name: "Анна",
              last_name: "Иванова",
              email: null,
              phone: null,
              custom_data: {},
              branch_id: "branch-a",
              source_id: "source-a",
              created_at: "2026-07-18T09:00:00.000Z",
              version: 1,
            },
          ],
        },
      ]);

      await expect(
        service.previewLeadSubscriptionPurchase(
          { userId: `${role}-a`, role },
          "lead-a",
          purchaseDto(),
        ),
      ).resolves.toEqual({ previewToken: "signed-preview" });

      const sql = String(query.mock.calls[0][0]);
      expect(sql).not.toContain("app.staff_branch_assignments");
      expect(query.mock.calls[0][1]).toEqual(["lead-a"]);
    },
  );

  describe("«Оплачено» по абонементу — из личного счёта", () => {
    it("читает приход, которым закрыт абонемент", async () => {
      const { service, query } = createService([
        {
          id: "sub-a",
          student_id: "student-a",
          student_user_id: "client-a",
          lessons_total: 10,
          lessons_used: 0,
          starts_at: null,
          expires_at: null,
          status: "active",
          created_at: "2026-06-01T00:00:00.000Z",
          updated_at: "2026-06-01T00:00:00.000Z",
          package_name: "10 занятий",
          package_price: "7000",
          paid_amount: "8000",
        },
      ]);

      const result = await service.listSubscriptions(schoolActor, { limit: 1 });

      // ✔ Решение владельца: оплату по абонементу считаем по личному счёту.
      // Выдача абонемента кладёт его стоимость на счёт (issueSubscription), и
      // «Оплачено» — это тот самый приход, а не отдельная сущность.
      expect(result.items[0]).toEqual(
        expect.objectContaining({ packagePrice: 7000, paidAmount: 8000 }),
      );
      // Переплата = 8000 − 7000 считается из этих двух чисел.
    });

    it("суммирует legacy и canonical оплаты по абонементу", async () => {
      const { service, query } = createService([]);

      await service.listSubscriptions(schoolActor, { limit: 1 });

      const sql = String(query.mock.calls[0][0]);
      // Строки в этих тестах замоканы, SQL не исполняется — поэтому сам запрос
      // проверяем текстом: и join, и то, что сумма берётся именно из прихода.
      expect(sql).toContain("left join lateral");
      expect(sql).toContain("from app.commerce_ordinary_payments payment");
      expect(sql).toContain("payment.id = sub.payment_id");
      expect(sql).toContain("payment.issued_subscription_id = sub.id");
      expect(sql).toContain(
        "sum(payment.amount_minor)::numeric / 100 as paid_amount",
      );
      expect(sql).toContain("payment.deleted_at is null");
    });
  });
});
