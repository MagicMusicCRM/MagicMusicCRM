import { ForbiddenException } from "@nestjs/common";
import { ActorClientProjectionFactory } from "../../access-control/actor-client-projection.factory";
import {
  ActorContext,
  UserRole,
} from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { CommerceProjectionFactory } from "./commerce-projection.factory";
import { CommerceProjectionRepository } from "./commerce-projection.repository";
import { CommerceProjectionService } from "./commerce-projection.service";
import {
  CommerceProjectionScope,
  CommerceProjectionSource,
} from "./commerce-projection.types";

const profiles: ReadonlyArray<[UserRole, string]> = [
  ["client", "client_self"],
  ["teacher", "teacher_assigned"],
  ["admin", "admin_scoped"],
  ["manager", "manager_scoped"],
  ["director", "director_scoped"],
  ["system_admin", "system_admin_emergency"],
];

const actor = (role: UserRole): ActorContext => ({
  userId: `user-${role}`,
  role,
});

const scope: CommerceProjectionScope = {
  studentId: "11111111-1111-4111-8111-111111111111",
  branchId: "22222222-2222-4222-8222-222222222222",
  timezoneName: "Europe/Moscow",
  accessVersion: 7,
  scopeKey:
    "branch:22222222-2222-4222-8222-222222222222:student:11111111-1111-4111-8111-111111111111",
};

const source = {
  studentId: scope.studentId,
  accounts: [
    {
      currencyCode: "RUB",
      actualPaymentsMinor: "640000",
      adjustmentsMinor: "-160000",
      obligationDebitsMinor: "800000",
      obligationCreditsMinor: "160000",
      writeOffsMinor: "0",
      balanceMinor: "0",
      debtMinor: "0",
      pendingMinor: "0",
      remainingObligationMinor: "0",
      audit: "must-not-leak",
    },
  ],
  subscriptions: [
    {
      id: "33333333-3333-4333-8333-333333333333",
      status: "active",
      startsAt: "2026-07-29",
      expiresAt: null,
      internal: "must-not-leak",
      units: {
        total: "8",
        used: "1",
        reserved: "1",
        paid: "6",
        available: "4",
        remaining: "7",
      },
      financial: {
        actualPaidMinor: "480000",
        obligationMinor: "640000",
        debtMinor: "160000",
        pendingMinor: "0",
        remainingObligationMinor: "160000",
        overpaymentMinor: "0",
        nextPaymentAt: "2026-08-29T10:00:00.000Z",
      },
      terms: {
        displayName: "8 занятий",
        validityDays: 60,
        basePriceMinor: "800000",
        finalPriceMinor: "640000",
        currencyCode: "RUB",
        commercialRules: { mutable: true },
        discount: {
          type: "percent",
          percentBasisPoints: 2000,
          reason: "Льгота",
          sourceRef: "must-not-leak",
        },
      },
      installments: [
        {
          installmentNumber: 1,
          dueAt: "2026-07-29T10:00:00.000Z",
          amountMinor: "640000",
          currencyCode: "RUB",
          status: "pending",
          createdBy: "must-not-leak",
        },
      ],
    },
  ],
  movements: [
    {
      id: "44444444-4444-4444-8444-444444444444",
      kind: "payment",
      direction: "credit",
      amountMinor: "640000",
      currencyCode: "RUB",
      occurredAt: "2026-07-29T10:00:00.000Z",
      method: "cashless",
      comment: "Проверить оплату за рассрочку",
      factType: null,
      chargeType: null,
      issuedSubscriptionId: "33333333-3333-4333-8333-333333333333",
      subscriptionName: "8 занятий",
      sourcePaymentId: null,
      sourceRef: "must-not-leak",
    },
  ],
  technicalHistory: [
    {
      id: "66666666-6666-4666-8666-666666666666",
      eventType: "monetary_reversal",
      paymentRecordId: "77777777-7777-4777-8777-777777777777",
      previousStatus: "paid",
      amountMinor: "640000",
      currencyCode: "RUB",
      sourceKind: "payment",
      sourceId: "44444444-4444-4444-8444-444444444444",
      counterpartKind: "account_adjustment",
      counterpartId: "88888888-8888-4888-8888-888888888888",
      reason: "Ошибочная оплата",
      actorUserId: "user-manager",
      actorName: "Управляющий",
      occurredAt: "2026-07-29T11:00:00.000Z",
    },
  ],
  scope,
  internal: "must-not-leak",
} as unknown as CommerceProjectionSource;

describe("v4 commerce projections contract", () => {
  const projectionFactory = () =>
    new CommerceProjectionFactory(new ActorClientProjectionFactory());

  afterEach(() => jest.useRealTimers());

  it("maps all six role profiles and partitions every readable cache by finance scope", () => {
    const factory = projectionFactory();
    for (const [role, profile] of profiles) {
      expect(factory.profileFor(actor(role))).toBe(profile);
    }

    const readableRoles: UserRole[] = [
      "client",
      "admin",
      "manager",
      "director",
      "system_admin",
    ];
    const keys = readableRoles.map((role) =>
      factory.cachePartitionKey(actor(role), scope),
    );
    expect(new Set(keys).size).toBe(readableRoles.length);
    expect(keys.every((key) => key.includes(":finance:"))).toBe(true);
    expect(() => factory.cachePartitionKey(actor("teacher"), scope)).toThrow(
      ForbiddenException,
    );
  });

  it("sanitizes client DTOs and only retains discount reason for staff", () => {
    const factory = projectionFactory();
    const clientProjection = factory.projectStudent(actor("client"), source);
    const staffProjection = factory.projectStudent(actor("manager"), source);

    expect(clientProjection.subscriptions[0]?.terms.discount).toEqual({
      type: "percent",
      percentBasisPoints: 2000,
    });
    expect(staffProjection.subscriptions[0]?.terms.discount).toEqual({
      type: "percent",
      percentBasisPoints: 2000,
      reason: "Льгота",
    });
    expect(clientProjection.technicalHistory).toEqual([]);
    expect(clientProjection.movements[0]?.comment).toBeNull();
    expect(staffProjection.movements[0]?.comment).toBe(
      source.movements[0]?.comment ?? null,
    );
    expect(staffProjection.technicalHistory).toEqual([
      expect.objectContaining({
        eventType: "monetary_reversal",
        reason: "Ошибочная оплата",
        actorName: "Управляющий",
      }),
    ]);
    expect(clientProjection.lessonBalance).toMatchObject({
      activeSubscriptionCount: 1,
      paid: "6",
      available: "4",
      debts: [{ currencyCode: "RUB", amountMinor: "160000" }],
    });
    for (const projection of [clientProjection, staffProjection]) {
      const payload = JSON.stringify(projection);
      expect(payload).not.toMatch(
        /sourceRef|audit|internal|commercialRules|createdBy/,
      );
    }
  });

  it("aggregates multiple active and free subscriptions without marking debt as paid", () => {
    const paid = source.subscriptions[0]!;
    const free = {
      ...paid,
      id: "55555555-5555-4555-8555-555555555555",
      expiresAt: "2099-08-15T00:00:00.000Z",
      units: {
        total: "2",
        used: "0",
        reserved: "0",
        paid: "2",
        available: "2",
        remaining: "2",
      },
      financial: {
        actualPaidMinor: "0",
        obligationMinor: "0",
        debtMinor: "0",
        pendingMinor: "0",
        remainingObligationMinor: "0",
        overpaymentMinor: "0",
        nextPaymentAt: null,
      },
    };
    const projection = projectionFactory().projectStudent(actor("manager"), {
      ...source,
      subscriptions: [paid, free],
    });

    expect(projection.lessonBalance).toEqual({
      activeSubscriptionCount: 2,
      total: "10",
      used: "1",
      reserved: "1",
      paid: "8",
      available: "6",
      debts: [{ currencyCode: "RUB", amountMinor: "160000" }],
      nextPaymentAt: "2026-08-29T10:00:00.000Z",
      expiresAt: "2099-08-15T00:00:00.000Z",
    });
  });

  it.each([
    {
      label: "keeps the subscription active through its final Moscow day",
      now: "2026-08-29T20:59:59.999Z",
      expectedStatus: "active",
      activeSubscriptionCount: 1,
      available: "4",
    },
    {
      label: "expires the subscription when the next Moscow day starts",
      now: "2026-08-29T21:00:00.000Z",
      expectedStatus: "expired",
      activeSubscriptionCount: 0,
      available: "0",
    },
  ])(
    "$label",
    ({ now, expectedStatus, activeSubscriptionCount, available }) => {
      jest.useFakeTimers().setSystemTime(new Date(now));

      const projection = projectionFactory().projectStudent(actor("manager"), {
        ...source,
        subscriptions: [
          {
            ...source.subscriptions[0]!,
            expiresAt: "2026-08-29",
          },
        ],
      });

      expect(projection.subscriptions[0]?.status).toBe(expectedStatus);
      expect(projection.lessonBalance).toMatchObject({
        activeSubscriptionCount,
        available,
      });
    },
  );

  it("uses the subscription branch date instead of the Moscow date", () => {
    jest.useFakeTimers().setSystemTime(new Date("2026-08-29T19:00:00.000Z"));

    const projection = projectionFactory().projectStudent(actor("manager"), {
      ...source,
      scope: {
        ...scope,
        timezoneName: "Asia/Yekaterinburg",
      },
      subscriptions: [
        {
          ...source.subscriptions[0]!,
          expiresAt: "2026-08-29",
        },
      ],
    });

    expect(projection.subscriptions[0]?.status).toBe("expired");
    expect(projection.lessonBalance).toMatchObject({
      activeSubscriptionCount: 0,
      available: "0",
    });
  });

  it("denies Teacher in the service before any repository call", async () => {
    const repositoryMock = {
      resolveSelfScopes: jest.fn(),
      resolveStudentScope: jest.fn(),
      loadProjection: jest.fn(),
    };
    const service = new CommerceProjectionService(
      repositoryMock as unknown as CommerceProjectionRepository,
      projectionFactory(),
    );

    await expect(service.readSelf(actor("teacher"))).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    await expect(
      service.readStudent(actor("teacher"), scope.studentId),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(repositoryMock.resolveSelfScopes).not.toHaveBeenCalled();
    expect(repositoryMock.resolveStudentScope).not.toHaveBeenCalled();
    expect(repositoryMock.loadProjection).not.toHaveBeenCalled();
  });

  it("returns the separate client self envelope without embedded internals", async () => {
    const selfScope = {
      ...scope,
      scopeKey: `self:student:${scope.studentId}`,
    };
    const repositoryMock = {
      resolveSelfScopes: jest.fn().mockResolvedValue([selfScope]),
      resolveStudentScope: jest.fn(),
      loadProjection: jest
        .fn()
        .mockResolvedValue([{ ...source, scope: selfScope }]),
    };
    const service = new CommerceProjectionService(
      repositoryMock as unknown as CommerceProjectionRepository,
      projectionFactory(),
    );

    const response = await service.readSelf(actor("client"));
    expect(response).toMatchObject({
      projection: "client_self",
      students: [{ studentId: scope.studentId }],
    });
    expect(response.students[0]?.subscriptions[0]?.terms.discount).toEqual({
      type: "percent",
      percentBasisPoints: 2000,
    });
    expect(repositoryMock.loadProjection).toHaveBeenCalledWith(
      actor("client"),
      [selfScope],
    );
  });

  it.each([
    ["client", "client_self"],
    ["admin", "admin_scoped"],
    ["manager", "manager_scoped"],
    ["director", "director_scoped"],
    ["system_admin", "system_admin_emergency"],
  ] as const)(
    "returns the actor-scoped card envelope for %s",
    async (role, profile) => {
      const repositoryMock = {
        resolveSelfScopes: jest.fn(),
        resolveStudentScope: jest.fn().mockResolvedValue(scope),
        loadProjection: jest.fn().mockResolvedValue([source]),
      };
      const service = new CommerceProjectionService(
        repositoryMock as unknown as CommerceProjectionRepository,
        projectionFactory(),
      );

      await expect(
        service.readStudent(actor(role), scope.studentId),
      ).resolves.toMatchObject({
        projection: profile,
        student: { studentId: scope.studentId },
      });
      expect(repositoryMock.resolveStudentScope).toHaveBeenCalledWith(
        actor(role),
        scope.studentId,
      );
      expect(repositoryMock.loadProjection).toHaveBeenCalledWith(actor(role), [
        scope,
      ]);
    },
  );

  it("allows Director cross-branch while keeping branch staff and emergency scopes distinct", async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [
        {
          student_id: scope.studentId,
          branch_id: scope.branchId,
          timezone_name: "Asia/Yekaterinburg",
          access_version: "7",
          created_at: "2026-07-29T10:00:00.000Z",
        },
      ],
    });
    const repository = new CommerceProjectionRepository({
      query,
    } as unknown as DatabaseService);

    await repository.resolveSelfScopes(actor("client"));
    await repository.resolveStudentScope(actor("client"), scope.studentId);
    await repository.resolveStudentScope(actor("manager"), scope.studentId);
    const directorScope = await repository.resolveStudentScope(
      actor("director"),
      scope.studentId,
    );
    const emergencyScope = await repository.resolveStudentScope(
      actor("system_admin"),
      scope.studentId,
    );

    const [selfSql, clientSql, staffSql, directorSql, emergencySql] =
      query.mock.calls.map((call) => String(call[0]));
    expect(selfSql).toContain("app.family_members");
    expect(selfSql).toContain("app.user_crm_links");
    expect(clientSql).toContain("account_profile.user_id = $1");
    expect(staffSql).toContain("app.staff_branch_assignments");
    expect(directorSql).not.toContain("app.staff_branch_assignments");
    expect(directorScope.scopeKey).toBe(
      `business:student:${scope.studentId}`,
    );
    expect(directorScope.timezoneName).toBe("Asia/Yekaterinburg");
    expect(directorSql).toContain("branch.timezone_name");
    expect(emergencySql).not.toContain("app.staff_branch_assignments");
    expect(emergencyScope.scopeKey).toBe(
      `emergency:student:${scope.studentId}`,
    );
  });

  it("hard-denies Teacher before SQL and batches immutable facts only", async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [
        {
          student_id: scope.studentId,
          accounts: [],
          subscriptions: [],
          movements: [],
        },
      ],
    });
    const repository = new CommerceProjectionRepository({
      query,
    } as unknown as DatabaseService);

    await expect(
      repository.loadProjection(actor("teacher"), [scope]),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(query).not.toHaveBeenCalled();

    await repository.loadProjection(actor("manager"), [scope]);
    const sql = String(query.mock.calls[0]?.[0]);
    expect(sql).toContain("app.subscriptions");
    expect(sql).toContain("commercial_snapshot");
    expect(sql).toContain("app.subscription_installments");
    expect(sql).toContain("app.commerce_ordinary_payments");
    expect(sql).toContain("payment.amount_minor");
    expect(sql).toContain("app.subscription_obligation_facts");
    expect(sql).toContain("app.lesson_client_charge_facts");
    expect(sql).toContain("app.lesson_reservations");
    expect(sql).toContain("app.commerce_ordinary_account_adjustments");
    expect(sql).toContain("app.commerce_ordinary_payment_records");
    expect(sql).toContain("app.commerce_reporting_exclusions");
    expect(sql).toContain("app.subscription_lifecycle_events");
    expect(sql).not.toMatch(
      /expected_payments|subscription_packages|lesson_participation|attendance/i,
    );
    expect(query).toHaveBeenCalledTimes(1);
    expect(query.mock.calls[0]?.[1]).toEqual([[scope.studentId], true]);
    await repository.loadProjection(actor("client"), [scope]);
    expect(query.mock.calls[1]?.[1]).toEqual([[scope.studentId], false]);
  });
});
