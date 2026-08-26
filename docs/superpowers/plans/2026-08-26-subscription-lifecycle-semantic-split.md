# Subscription Lifecycle Semantic Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Remove the SubscriptionLifecycleService god-class finding while preserving replacement and cancellation behavior, atomicity, public API, and evidence quality.

**Architecture:** Keep SubscriptionLifecycleService as the controller-facing facade. Extract pure command/preview guards and replacement/cancellation policies, then move each complete executeVersionedMutation boundary into its own executor service; transaction callbacks must never be split across services.

**Tech Stack:** NestJS 11, TypeScript 5.8, Jest 30, PostgreSQL/PGlite integration fixtures, RepoWise, Sentrux.

**Spec:** docs/superpowers/specs/2026-08-25-production-code-health-recovery-design.md

## Global Constraints

- Work from exact baseline commit 712db2dd3a87b0adb43bb73ed988ce35c1e6cf28 on branch codex/crm-configuration-semantic-cut.
- Compare against the approved exact pre-package evidence: RepoWise index 9963adb8, target health 3.44, NLOC 1350, max CCN 14, deficit 6156, and truthful production coverage SHA 861d with 86.52% lines / 82.81% branches.
- Preserve the four public SubscriptionLifecycleService methods and their argument/response contracts; SubscriptionCommerceController must not change.
- Preserve one complete executeVersionedMutation call and mutate callback per command.
- Preserve expected version, stable replay, preview-token binding/currentness, deterministic student lock ordering, idempotency, audit/outbox, append-only payments/reservations/facts, RBAC, and resource scope.
- Do not modify SubscriptionLifecycleRepository, SubscriptionIssueRepository, SubscriptionReservationService, SubscriptionPreviewTokenService, PlatformIntegrityService, DTOs, schema, migrations, or production data.
- The facade may contain composition and delegation only; it may not retain policy, persistence, transaction callbacks, or copied decision logic.
- New semantic owners target health >=7.0, max CCN <=10, and no god_class or brain_method. Any lower headline requires history/co-change-only evidence with no live structural defect.
- Package acceptance requires the production god count to decrease, RepoWise consumers/cycles/conformance to remain clean, and Sentrux quality >=5736, depth <=13, perfect acyclicity, and rules 2/2.
- UI/API text remains Russian; code and comments remain English.
- Every code task uses TDD, focused verification, RepoWise index refresh, Sentrux rescan, an independent task review, and a separate reversible commit.

---

## File Structure

| File | Responsibility |
|---|---|
| server/src/crm/commerce/subscription-lifecycle.types.ts | Shared mutation metadata, result refs, and warning value type |
| server/src/crm/commerce/subscription-lifecycle-command.policy.ts | Command validation, actor/student/token binding, deterministic IDs |
| server/src/crm/commerce/subscription-replacement.policy.ts | Pure replacement validation, calculation, reservation plan, snapshot, token facts, warnings |
| server/src/crm/commerce/subscription-cancellation.policy.ts | Pure cancellation validation, refund calculation/cap, token facts, warnings |
| server/src/crm/commerce/subscription-replacement.service.ts | Replacement preview and the complete replacement versioned transaction |
| server/src/crm/commerce/subscription-cancellation.service.ts | Cancellation preview and the complete cancellation versioned transaction |
| server/src/crm/commerce/subscription-lifecycle.service.ts | Small controller-facing facade over both executor services |
| server/src/crm/commerce/subscription-lifecycle-boundaries.spec.ts | Structural ownership and facade regression guard |

### Task 1: Shared contracts and command/preview guard

**Files:**
- Create: server/src/crm/commerce/subscription-lifecycle.types.ts
- Create: server/src/crm/commerce/subscription-lifecycle-command.policy.ts
- Create: server/src/crm/commerce/subscription-lifecycle-command.policy.spec.ts
- Modify: server/src/crm/commerce/subscription-lifecycle.service.ts
- Modify: server/src/crm/crm.module.ts
- Modify: server/src/crm/commerce/subscription-replace-postgres.integration.spec.ts
- Modify: server/src/crm/commerce/subscription-cancel-postgres.integration.spec.ts

**Interfaces:**
- Consumes: SubscriptionReplaceCommandDto, SubscriptionCancelCommandDto, SubscriptionReplacePreviewTokenPayload, SubscriptionCancelPreviewTokenPayload, ActorContext.
- Produces: SubscriptionLifecycleMutationMetadata, ReplacementResultRef, CancellationResultRef, SubscriptionLifecycleCommandPolicy.

- [ ] **Step 1: Write the failing command-policy tests**

Create the spec with these exact cases:

~~~typescript
import {
  BadRequestException,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { SubscriptionLifecycleCommandPolicy } from "./subscription-lifecycle-command.policy";

describe("SubscriptionLifecycleCommandPolicy", () => {
  const policy = new SubscriptionLifecycleCommandPolicy();
  const metadata = {
    idempotencyKey: "replace-key-001",
    requestId: "request-001",
  };

  it("validates replacement confirmation, version, reason, token and metadata", () => {
    expect(() =>
      policy.assertReplacementCommand(
        {
          confirm: false,
          expectedVersion: 1,
          reason: "Причина",
          previewToken: "signed",
        } as never,
        metadata,
      ),
    ).toThrow(UnprocessableEntityException);
    expect(() =>
      policy.assertReplacementCommand(
        {
          confirm: true as const,
          expectedVersion: 1,
          reason: "Причина",
          previewToken: "signed",
        },
        { ...metadata, idempotencyKey: "short" },
      ),
    ).toThrow(BadRequestException);
  });

  it("binds actor, student, subscription and expected version", () => {
    const payload = {
      actorUserId: "actor-1",
      studentId: "student-1",
      issuedSubscriptionId: "subscription-1",
      expectedVersion: 3,
    };
    expect(() =>
      policy.assertReplacementTokenBinding(
        payload as never,
        { userId: "actor-2", role: "director" },
        "student-1",
        "subscription-1",
        3,
      ),
    ).toThrow(UnprocessableEntityException);
    expect(() =>
      policy.assertStudentScope({ studentId: "student-2" }, "student-1"),
    ).toThrow(NotFoundException);
  });

  it("derives a stable replacement id from actor, operation and key", () => {
    expect(
      policy.deterministicId(
        "actor-1",
        "crm.subscription.replace",
        "replace-key-001",
      ),
    ).toBe("d3cff883-9392-4a0e-b7d1-cd4883852a03");
  });
});
~~~

- [ ] **Step 2: Run the test and verify the missing-owner failure**

Run from server:

~~~bash
npm test -- --runTestsByPath src/crm/commerce/subscription-lifecycle-command.policy.spec.ts
~~~

Expected: FAIL because subscription-lifecycle-command.policy.ts does not exist.

- [ ] **Step 3: Create the shared contracts and policy**

Move the three existing public interfaces unchanged into subscription-lifecycle.types.ts and add the shared LifecycleWarning value type:

~~~typescript
export interface SubscriptionLifecycleMutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

export interface ReplacementResultRef extends Record<string, unknown> {
  sourceId: string;
  sourceVersion: number;
  resultId: string;
  resultVersion: number;
  payerStudentId: string;
  newPackageId: string;
  newPackageVersion: number;
  usedUnits: string;
  transferredReservationCount: number;
  transferredReservationUnits: string;
  releasedReservationCount: number;
  releasedReservationUnits: string;
  deltaMinor: string;
  positionKind: "debt" | "overpayment" | "settled";
  positionMinor: string;
  ccy: string;
  obligationFactId: string | null;
}

export interface CancellationResultRef extends Record<string, unknown> {
  sourceId: string;
  resultVersion: number;
  state: "cancelled";
  payerStudentId: string;
  releasedCount: number;
  releasedUnits: string;
  futureCount: number;
  closedRecordCount: number;
  confirmedFundedMinor: string;
  previousRefundMinor: string;
  unusedUnits: string;
  unfundedCancellationMinor: string;
  chosenRefundMinor: string;
  totalCreditMinor: string;
  creditFactId: string | null;
}

export interface LifecycleWarning {
  code: string;
  count?: number;
  units?: string;
  message: string;
}
~~~

Create an injectable SubscriptionLifecycleCommandPolicy exposing exactly:

~~~typescript
@Injectable()
export class SubscriptionLifecycleCommandPolicy {
  assertReplacementCommand(
    dto: SubscriptionReplaceCommandDto,
    metadata: SubscriptionLifecycleMutationMetadata,
  ): void;
  assertCancellationCommand(
    dto: SubscriptionCancelCommandDto,
    metadata: SubscriptionLifecycleMutationMetadata,
  ): void;
  assertReplacementTokenBinding(
    payload: SubscriptionReplacePreviewTokenPayload,
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    expectedVersion: number,
  ): void;
  assertCancellationTokenBinding(
    payload: SubscriptionCancelPreviewTokenPayload,
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    expectedVersion: number,
  ): void;
  assertStudentScope(context: { studentId: string }, studentId: string): void;
  deterministicId(
    actorUserId: string,
    operation: string,
    idempotencyKey: string,
  ): string;
}
~~~

Relocate the existing assertCommand, assertCancelCommand, both token-binding methods, assertStudentScope, and deterministicId bodies without changing error codes/messages or hashing input. Re-export the three public result/metadata types from subscription-lifecycle.service.ts, inject the policy into the old service, and replace each relocated call with the corresponding policy call.

The service constructor at the end of this task is exactly:

~~~typescript
constructor(
  private readonly repository: SubscriptionLifecycleRepository,
  private readonly issueRepository: SubscriptionIssueRepository,
  private readonly policy: CrmPolicy,
  private readonly integrity: PlatformIntegrityService,
  private readonly previewTokens: SubscriptionPreviewTokenService,
  private readonly reservations: SubscriptionReservationService,
  private readonly commands: SubscriptionLifecycleCommandPolicy,
) {}
~~~

- [ ] **Step 4: Wire DI and update both integration fixtures**

Add SubscriptionLifecycleCommandPolicy to CrmModule providers. Instantiate one policy in each replacement/cancellation integration setup and pass it to SubscriptionLifecycleService after the existing six constructor dependencies.

- [ ] **Step 5: Run focused verification**

~~~bash
npm test -- --runTestsByPath src/crm/commerce/subscription-lifecycle-command.policy.spec.ts src/crm/commerce/subscription-replace-postgres.integration.spec.ts src/crm/commerce/subscription-cancel-postgres.integration.spec.ts
npm run typecheck
~~~

Expected: command-policy tests and all 10 existing replacement/cancellation integration cases pass; typecheck exits zero.

- [ ] **Step 6: Refresh architecture evidence and commit**

Run RepoWise update, targeted health, Sentrux rescan/health/rules, and diff check. Commit:

~~~bash
git add server/src/crm/commerce/subscription-lifecycle.types.ts server/src/crm/commerce/subscription-lifecycle-command.policy.ts server/src/crm/commerce/subscription-lifecycle-command.policy.spec.ts server/src/crm/commerce/subscription-lifecycle.service.ts server/src/crm/crm.module.ts server/src/crm/commerce/subscription-replace-postgres.integration.spec.ts server/src/crm/commerce/subscription-cancel-postgres.integration.spec.ts
git commit -m "refactor(commerce): extract lifecycle command policy"
~~~

### Task 2: Replacement policy

**Files:**
- Create: server/src/crm/commerce/subscription-replacement.policy.ts
- Create: server/src/crm/commerce/subscription-replacement.policy.spec.ts
- Modify: server/src/crm/commerce/subscription-lifecycle.service.ts
- Modify: server/src/crm/crm.module.ts
- Modify: both lifecycle integration fixtures

**Interfaces:**
- Consumes: ActorContext, ReplacementContext, ReplacementPackageRow, IssuedCommercialSnapshot.
- Produces: ReplacementReadyContext, ReplacementCalculation, ReplacementReservationPlan, SubscriptionReplacementPolicy.

Define the produced value types in subscription-replacement.policy.ts:

~~~typescript
export type ReplacementReadyContext = ReplacementContext & {
  newPackage: NonNullable<ReplacementContext["newPackage"]>;
};

export interface ReplacementCalculation {
  deltaMinor: bigint;
  positionMinor: bigint;
  positionKind: "debt" | "overpayment" | "settled";
}

export interface ReplacementReservationPlan {
  transferReservationIds: string[];
  releaseReservationIds: string[];
  transferredUnits: string;
  releasedUnits: string;
}
~~~

- [ ] **Step 1: Write failing pure-policy tests**

Use a complete ReplacementContext factory whose baseline has old final 800000, new final 1000000, actual paid 600000, used units 2, new volume 7, reservations of 3/2/1 units, and one future lesson. Assert:

~~~typescript
const context: ReplacementReadyContext = {
  issuedSubscriptionId: "subscription-old",
  studentId: "student-1",
  payerStudentId: "payer-1",
  fundingMode: "installment",
  purchaseReason: "upgrade",
  oldPackageId: "package-old",
  oldStatus: "active",
  oldVersion: 3,
  oldFinalPriceMinor: "800000",
  oldCurrencyCode: "RUB",
  legacyLessonsUsed: "2",
  newPackage: {
    id: "package-new",
    name: "New package",
    unitCount: "7",
    basePriceMinor: "1000000",
    currencyCode: "RUB",
    validityDays: 30,
    active: true,
    version: 2,
    deletedAt: null,
  },
  usedUnits: "2",
  actualPaidMinor: "600000",
  reservedLessonCount: 3,
  reservedUnits: "6",
  reservedRows: [
    {
      reservationId: "reservation-1",
      lessonId: "lesson-1",
      scheduledAt: "2026-09-01T10:00:00.000Z",
      units: "3",
    },
    {
      reservationId: "reservation-2",
      lessonId: "lesson-2",
      scheduledAt: "2026-09-02T10:00:00.000Z",
      units: "2",
    },
    {
      reservationId: "reservation-3",
      lessonId: "lesson-3",
      scheduledAt: "2026-09-03T10:00:00.000Z",
      units: "1",
    },
  ],
  futureLessonCount: 1,
  futureUnits: "1",
};

const calculation = policy.calculate(context);
expect(calculation).toEqual({
  deltaMinor: 200000n,
  positionMinor: 400000n,
  positionKind: "debt",
});

expect(policy.planReservations(context)).toEqual({
  transferReservationIds: ["reservation-1", "reservation-2"],
  releaseReservationIds: ["reservation-3"],
  transferredUnits: "5",
  releasedUnits: "1",
});

expect(policy.warnings(context).map((warning) => warning.code)).toEqual([
  "USED_UNITS_TRANSFERRED",
  "FUTURE_LESSONS_PRESERVED",
  "RESERVATIONS_RELEASED_FOR_CAPACITY",
  "ACTUAL_PAYMENTS_PRESERVED",
]);
~~~

Add explicit tests for inactive/archived package, cross-currency replacement, volume below used units, stale token facts, and commercial snapshot fields.

- [ ] **Step 2: Verify the missing-policy failure**

~~~bash
npm test -- --runTestsByPath src/crm/commerce/subscription-replacement.policy.spec.ts
~~~

Expected: FAIL because subscription-replacement.policy.ts does not exist.

- [ ] **Step 3: Implement the replacement policy**

Expose these exact methods:

~~~typescript
@Injectable()
export class SubscriptionReplacementPolicy {
  assertContext(
    context: ReplacementContext | null,
  ): asserts context is ReplacementReadyContext;
  calculate(context: ReplacementReadyContext): ReplacementCalculation;
  planReservations(
    context: ReplacementReadyContext,
  ): ReplacementReservationPlan;
  createSnapshot(
    oldIssuedSubscriptionId: string,
    context: ReplacementReadyContext,
    packageRow: ReplacementPackageRow,
  ): IssuedCommercialSnapshot;
  createTokenPayload(
    actor: ActorContext,
    context: ReplacementReadyContext,
  ): Omit<
    SubscriptionReplacePreviewTokenPayload,
    "issuedAtSeconds" | "expiresAtSeconds"
  >;
  assertPreviewCurrent(
    signed: SubscriptionReplacePreviewTokenPayload,
    current: Omit<
      SubscriptionReplacePreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
  ): void;
  warnings(context: ReplacementReadyContext): LifecycleWarning[];
}
~~~

Relocate replacement-only methods and their unit conversion helpers. Replace old-service calls with replacementPolicy calls; remove the old methods immediately so no duplicate policy remains. Add the policy to CrmModule and both direct integration constructors.

Append replacementPolicy after commands in the service constructor and in both integration fixtures. No other constructor order changes in this task.

- [ ] **Step 4: Run pure and integration tests**

~~~bash
npm test -- --runTestsByPath src/crm/commerce/subscription-replacement.policy.spec.ts src/crm/commerce/subscription-replace-postgres.integration.spec.ts src/crm/commerce/subscription-cancel-postgres.integration.spec.ts
npm run typecheck
~~~

Expected: all tests pass and the old service contains no replacement calculation, reservation-plan, snapshot, warning, token-facts, or preview-currentness method.

- [ ] **Step 5: Refresh metrics and commit**

Run `repowise update --index-only`, targeted RepoWise health/risk, Sentrux rescan/health/rules, and `git diff --check` before committing.

~~~bash
git add server/src/crm/commerce/subscription-replacement.policy.ts server/src/crm/commerce/subscription-replacement.policy.spec.ts server/src/crm/commerce/subscription-lifecycle.service.ts server/src/crm/crm.module.ts server/src/crm/commerce/subscription-replace-postgres.integration.spec.ts server/src/crm/commerce/subscription-cancel-postgres.integration.spec.ts
git commit -m "refactor(commerce): extract replacement policy"
~~~

### Task 3: Cancellation policy

**Files:**
- Create: server/src/crm/commerce/subscription-cancellation.policy.ts
- Create: server/src/crm/commerce/subscription-cancellation.policy.spec.ts
- Modify: server/src/crm/commerce/subscription-lifecycle.service.ts
- Modify: server/src/crm/crm.module.ts
- Modify: both lifecycle integration fixtures

**Interfaces:**
- Consumes: ActorContext, CancellationContext, SubscriptionCancelPreviewTokenPayload.
- Produces: CancellationCalculation, SubscriptionCancellationPolicy.

Define the produced calculation type in subscription-cancellation.policy.ts:

~~~typescript
export interface CancellationCalculation {
  confirmedFundedMinor: bigint;
  previousRefundMinor: bigint;
  unusedUnits: bigint;
  unusedValueMinor: bigint;
  unfundedCancellationMinor: bigint;
  recommendedRefundMinor: bigint;
}
~~~

- [ ] **Step 1: Write failing cancellation-policy tests**

Use a complete CancellationContext with 10 total units, 2 used, 2 reserved, final 800000, installment funding, actual paid 500000, and prior refund 10000. Assert:

~~~typescript
const context: CancellationContext = {
  issuedSubscriptionId: "subscription-1",
  studentId: "student-1",
  payerStudentId: "payer-1",
  fundingMode: "installment",
  package: {
    id: "package-1",
    name: "Package",
    version: 2,
    unitCount: "10",
  },
  status: "active",
  version: 4,
  currencyCode: "RUB",
  finalMinor: "800000",
  usedUnits: "2",
  actualPaidMinor: "500000",
  previousRefundMinor: "10000",
  writeoffMinor: "20000",
  netObligationMinor: "300000",
  balanceMinor: "100000",
  paymentRefs: [
    {
      id: "payment-1",
      amountMinor: "500000",
      occurredAt: "2026-08-01T10:00:00.000Z",
    },
  ],
  previousRefundRefs: [
    {
      id: "refund-1",
      amountMinor: "10000",
      occurredAt: "2026-08-10T10:00:00.000Z",
    },
  ],
  openPaymentRecordRefs: [
    {
      id: "record-1",
      status: "unpaid",
      version: 1,
      amountMinor: "300000",
    },
  ],
  writeoffRefs: [
    {
      id: "writeoff-1",
      lessonId: "lesson-used",
      amountMinor: "20000",
      units: "2",
      occurredAt: "2026-08-15T10:00:00.000Z",
    },
  ],
  obligationRefs: [
    {
      id: "obligation-1",
      direction: "debit",
      amountMinor: "300000",
      occurredAt: "2026-08-01T10:00:00.000Z",
    },
  ],
  futureLessonCount: 1,
  reservedLessonCount: 1,
  reservedUnits: "2",
  futureLessons: [
    {
      lessonId: "lesson-future",
      reservationId: "reservation-1",
      scheduledAt: "2026-09-01T10:00:00.000Z",
      units: "2",
      reserved: true,
    },
  ],
};

expect(policy.calculate(context)).toEqual({
  confirmedFundedMinor: 500000n,
  previousRefundMinor: 10000n,
  unusedUnits: 600n,
  unusedValueMinor: 480000n,
  unfundedCancellationMinor: 190000n,
  recommendedRefundMinor: 290000n,
});
expect(() => policy.assertRefundWithinCap("290001", 290000n)).toThrow(
  UnprocessableEntityException,
);
expect(policy.warnings(context).map((warning) => warning.code)).toEqual([
  "FUTURE_LESSONS_PRESERVED",
  "RESERVATIONS_RELEASED",
  "ACTUAL_PAYMENTS_PRESERVED",
  "WRITEOFFS_PRESERVED",
]);
~~~

Also test personal-account funding, zero/invalid package units, inactive context, exact refund cap, and stale cancellation token facts.

- [ ] **Step 2: Verify the missing-policy failure**

~~~bash
npm test -- --runTestsByPath src/crm/commerce/subscription-cancellation.policy.spec.ts
~~~

Expected: FAIL because subscription-cancellation.policy.ts does not exist.

- [ ] **Step 3: Implement and wire the cancellation policy**

Expose:

~~~typescript
@Injectable()
export class SubscriptionCancellationPolicy {
  assertContext(
    context: CancellationContext | null,
  ): asserts context is CancellationContext;
  calculate(context: CancellationContext): CancellationCalculation;
  assertRefundWithinCap(
    refundMinor: string,
    recommendedRefundMinor: bigint,
  ): bigint;
  createTokenPayload(
    actor: ActorContext,
    context: CancellationContext,
  ): Omit<
    SubscriptionCancelPreviewTokenPayload,
    "issuedAtSeconds" | "expiresAtSeconds"
  >;
  assertPreviewCurrent(
    signed: SubscriptionCancelPreviewTokenPayload,
    current: Omit<
      SubscriptionCancelPreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
  ): void;
  warnings(context: CancellationContext): LifecycleWarning[];
}
~~~

Move all cancellation-only bodies out of the old service and replace the inline refund cap with assertRefundWithinCap. Add the provider and constructor argument everywhere.

Append cancellationPolicy after replacementPolicy in the service constructor and in both integration fixtures. The old service still owns both transaction methods at this checkpoint.

- [ ] **Step 4: Run focused verification, refresh metrics, and commit**

~~~bash
npm test -- --runTestsByPath src/crm/commerce/subscription-cancellation.policy.spec.ts src/crm/commerce/subscription-cancel-postgres.integration.spec.ts src/crm/commerce/subscription-replace-postgres.integration.spec.ts
npm run typecheck
repowise update --index-only
git add server/src/crm/commerce/subscription-cancellation.policy.ts server/src/crm/commerce/subscription-cancellation.policy.spec.ts server/src/crm/commerce/subscription-lifecycle.service.ts server/src/crm/crm.module.ts server/src/crm/commerce/subscription-replace-postgres.integration.spec.ts server/src/crm/commerce/subscription-cancel-postgres.integration.spec.ts
git commit -m "refactor(commerce): extract cancellation policy"
~~~

Between the RepoWise update and commit, query targeted health/risk and run Sentrux rescan/health/rules plus `git diff --check`.

### Task 4: Replacement executor

**Files:**
- Create: server/src/crm/commerce/subscription-replacement.service.ts
- Modify: server/src/crm/commerce/subscription-lifecycle.service.ts
- Modify: server/src/crm/crm.module.ts
- Modify: both lifecycle integration fixtures

**Interfaces:**
- Consumes: repositories, CrmPolicy, PlatformIntegrityService, SubscriptionPreviewTokenService, SubscriptionReservationService, command policy, replacement policy.
- Produces: SubscriptionReplacementService.preview and SubscriptionReplacementService.execute.

- [ ] **Step 1: Change the replacement fixture to require the new executor**

Instantiate SubscriptionReplacementService and pass it as the final facade constructor dependency. Keep every existing replacement assertion unchanged.

~~~typescript
const replacementService = new SubscriptionReplacementService(
  lifecycleRepository,
  issueRepository,
  policy,
  integrity,
  previewTokens,
  reservations,
  commandPolicy,
  replacementPolicy,
);
~~~

- [ ] **Step 2: Verify the missing-executor failure**

~~~bash
npm test -- --runTestsByPath src/crm/commerce/subscription-replace-postgres.integration.spec.ts
~~~

Expected: FAIL because SubscriptionReplacementService is not defined.

- [ ] **Step 3: Move the complete replacement boundary**

Create:

~~~typescript
@Injectable()
export class SubscriptionReplacementService {
  async preview(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    dto: SubscriptionReplacePreviewDto,
  );

  async execute(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    dto: SubscriptionReplaceCommandDto,
    metadata: SubscriptionLifecycleMutationMetadata,
  );
}
~~~

Relocate previewReplacement lines 112-171 and replace lines 173-446 from baseline 712db2dd into preview/execute. Keep the entire executeVersionedMutation object, mutate callback, lock order, result mapping, audit mutation, outbox payload, replay check, and publishPostCommit call in this one service. Substitute only named policy calls.

Replace the facade methods with:

~~~typescript
previewReplacement(actor, studentId, issuedSubscriptionId, dto) {
  return this.replacement.preview(actor, studentId, issuedSubscriptionId, dto);
}

replace(actor, studentId, issuedSubscriptionId, dto, metadata) {
  return this.replacement.execute(
    actor,
    studentId,
    issuedSubscriptionId,
    dto,
    metadata,
  );
}
~~~

Retain the original explicit parameter and return types on both facade methods; the abbreviated delegation above specifies bodies only.

Add SubscriptionReplacementService to CrmModule. Update the cancellation fixture constructor without weakening cancellation assertions.

After the move, the transitional facade constructor retains cancellation dependencies in this exact order:

~~~typescript
constructor(
  private readonly repository: SubscriptionLifecycleRepository,
  private readonly issueRepository: SubscriptionIssueRepository,
  private readonly policy: CrmPolicy,
  private readonly integrity: PlatformIntegrityService,
  private readonly previewTokens: SubscriptionPreviewTokenService,
  private readonly reservations: SubscriptionReservationService,
  private readonly commands: SubscriptionLifecycleCommandPolicy,
  private readonly cancellationPolicy: SubscriptionCancellationPolicy,
  private readonly replacement: SubscriptionReplacementService,
) {}
~~~

- [ ] **Step 4: Run replacement, cancellation and type gates**

~~~bash
npm test -- --runTestsByPath src/crm/commerce/subscription-replacement.policy.spec.ts src/crm/commerce/subscription-lifecycle-command.policy.spec.ts src/crm/commerce/subscription-replace-postgres.integration.spec.ts src/crm/commerce/subscription-cancel-postgres.integration.spec.ts
npm run typecheck
~~~

Expected: all replacement/cancellation cases pass; facade contains no replacement repository or transaction logic.

- [ ] **Step 5: Refresh metrics and commit**

Run `repowise update --index-only`, targeted RepoWise health/risk, Sentrux rescan/health/rules, and `git diff --check` before committing.

~~~bash
git add server/src/crm/commerce/subscription-replacement.service.ts server/src/crm/commerce/subscription-lifecycle.service.ts server/src/crm/crm.module.ts server/src/crm/commerce/subscription-replace-postgres.integration.spec.ts server/src/crm/commerce/subscription-cancel-postgres.integration.spec.ts
git commit -m "refactor(commerce): extract replacement executor"
~~~

### Task 5: Cancellation executor and thin facade

**Files:**
- Create: server/src/crm/commerce/subscription-cancellation.service.ts
- Modify: server/src/crm/commerce/subscription-lifecycle.service.ts
- Modify: server/src/crm/crm.module.ts
- Modify: both lifecycle integration fixtures

**Interfaces:**
- Consumes: the same persistence/integrity services plus command and cancellation policies.
- Produces: SubscriptionCancellationService.preview/execute and final thin SubscriptionLifecycleService facade.

- [ ] **Step 1: Change the cancellation fixture to require the new executor**

~~~typescript
const cancellationService = new SubscriptionCancellationService(
  lifecycleRepository,
  issueRepository,
  policy,
  integrity,
  previewTokens,
  reservations,
  commandPolicy,
  cancellationPolicy,
);
~~~

Construct the facade with only replacementService and cancellationService.

- [ ] **Step 2: Verify the missing-executor failure**

~~~bash
npm test -- --runTestsByPath src/crm/commerce/subscription-cancel-postgres.integration.spec.ts
~~~

Expected: FAIL because SubscriptionCancellationService is not defined.

- [ ] **Step 3: Move the complete cancellation boundary**

Create:

~~~typescript
@Injectable()
export class SubscriptionCancellationService {
  async preview(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
  );

  async execute(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    dto: SubscriptionCancelCommandDto,
    metadata: SubscriptionLifecycleMutationMetadata,
  );
}
~~~

Relocate previewCancellation lines 448-518 and cancel lines 520-794 from baseline 712db2dd. Keep random audit ID creation, the complete transaction callback, token verification inside mutate, exact lock order, refund cap, reservation/payment-record count checks, credit/lifecycle facts, audit mutation, outbox, replay behavior, and post-commit publish together.

Reduce SubscriptionLifecycleService to:

~~~typescript
@Injectable()
export class SubscriptionLifecycleService {
  constructor(
    private readonly replacement: SubscriptionReplacementService,
    private readonly cancellation: SubscriptionCancellationService,
  ) {}

  previewReplacement(actor, studentId, issuedSubscriptionId, dto) {
    return this.replacement.preview(actor, studentId, issuedSubscriptionId, dto);
  }

  replace(actor, studentId, issuedSubscriptionId, dto, metadata) {
    return this.replacement.execute(
      actor,
      studentId,
      issuedSubscriptionId,
      dto,
      metadata,
    );
  }

  previewCancellation(actor, studentId, issuedSubscriptionId) {
    return this.cancellation.preview(actor, studentId, issuedSubscriptionId);
  }

  cancel(actor, studentId, issuedSubscriptionId, dto, metadata) {
    return this.cancellation.execute(
      actor,
      studentId,
      issuedSubscriptionId,
      dto,
      metadata,
    );
  }
}
~~~

Use explicit parameter types from the original facade; do not introduce implicit any. Add SubscriptionCancellationService to CrmModule and update both integration graphs.

- [ ] **Step 4: Run focused and commerce gates**

~~~bash
npm test -- --runTestsByPath src/crm/commerce/subscription-lifecycle-command.policy.spec.ts src/crm/commerce/subscription-replacement.policy.spec.ts src/crm/commerce/subscription-cancellation.policy.spec.ts src/crm/commerce/subscription-replace-postgres.integration.spec.ts src/crm/commerce/subscription-cancel-postgres.integration.spec.ts src/crm/commerce/subscription-lesson-race-postgres.integration.spec.ts
npm run typecheck
npm run build
~~~

Expected: all focused tests, typecheck, and build pass; controller source and public method names are unchanged.

- [ ] **Step 5: Refresh metrics and commit**

Run `repowise update --index-only`, targeted RepoWise health/risk, Sentrux rescan/health/rules, and `git diff --check` before committing.

~~~bash
git add server/src/crm/commerce/subscription-cancellation.service.ts server/src/crm/commerce/subscription-lifecycle.service.ts server/src/crm/crm.module.ts server/src/crm/commerce/subscription-replace-postgres.integration.spec.ts server/src/crm/commerce/subscription-cancel-postgres.integration.spec.ts
git commit -m "refactor(commerce): extract cancellation executor"
~~~

### Task 6: Structural ownership guard

**Files:**
- Create: server/src/crm/commerce/subscription-lifecycle-boundaries.spec.ts
- Modify only if the guard exposes a real boundary defect: the six Package 9 production owners and crm.module.ts

**Interfaces:**
- Consumes: exact file paths and source ownership contracts.
- Produces: permanent anti-regression guard for facade size, transaction placement, and policy purity.

- [ ] **Step 1: Write the structural test**

~~~typescript
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

describe("subscription lifecycle ownership boundaries", () => {
  const root = resolve(process.cwd(), "src", "crm", "commerce");
  const source = (name: string) =>
    readFileSync(resolve(root, name), "utf8");

  it("keeps each lifecycle responsibility in a named semantic owner", () => {
    for (const owner of [
      "subscription-lifecycle-command.policy.ts",
      "subscription-replacement.policy.ts",
      "subscription-cancellation.policy.ts",
      "subscription-replacement.service.ts",
      "subscription-cancellation.service.ts",
      "subscription-lifecycle.service.ts",
    ]) {
      expect(existsSync(resolve(root, owner))).toBe(true);
    }
  });

  it("keeps SubscriptionLifecycleService as a small transaction-free facade", () => {
    const facade = source("subscription-lifecycle.service.ts");
    const nloc = facade
      .split(/\r?\n/)
      .filter((line) => line.trim() && !line.trim().startsWith("//")).length;
    expect(nloc).toBeLessThanOrEqual(110);
    expect(facade).not.toContain("executeVersionedMutation");
    expect(facade).not.toContain("SubscriptionLifecycleRepository");
    expect(facade).not.toContain("PlatformIntegrityService");
    expect(facade).toContain("SubscriptionReplacementService");
    expect(facade).toContain("SubscriptionCancellationService");
  });

  it("keeps one complete transaction boundary in each executor", () => {
    const replacement = source("subscription-replacement.service.ts");
    const cancellation = source("subscription-cancellation.service.ts");
    expect(replacement.match(/executeVersionedMutation/g)).toHaveLength(1);
    expect(cancellation.match(/executeVersionedMutation/g)).toHaveLength(1);
    expect(replacement).toContain('operation: "crm.subscription.replace"');
    expect(cancellation).toContain('operation: "crm.subscription.cancel"');
    expect(replacement).toContain("publishPostCommit");
    expect(cancellation).toContain("publishPostCommit");
  });

  it("keeps pure policies free of persistence and integrity orchestration", () => {
    for (const name of [
      "subscription-lifecycle-command.policy.ts",
      "subscription-replacement.policy.ts",
      "subscription-cancellation.policy.ts",
    ]) {
      const policy = source(name);
      expect(policy).not.toContain("PlatformIntegrityService");
      expect(policy).not.toContain("DatabaseService");
      expect(policy).not.toContain("PoolClient");
      expect(policy).not.toContain("executeVersionedMutation");
    }
  });
});
~~~

- [ ] **Step 2: Run the guard and fix only concrete boundary failures**

~~~bash
npm test -- --runTestsByPath src/crm/commerce/subscription-lifecycle-boundaries.spec.ts
~~~

Expected: 4/4 pass. If a failure identifies retained facade logic, move that exact logic to its existing semantic owner; do not weaken limits or forbidden strings.

- [ ] **Step 3: Run focused regression, refresh metrics, and commit**

~~~bash
npm test -- --runTestsByPath src/crm/commerce/subscription-lifecycle-boundaries.spec.ts src/crm/commerce/subscription-lifecycle-command.policy.spec.ts src/crm/commerce/subscription-replacement.policy.spec.ts src/crm/commerce/subscription-cancellation.policy.spec.ts src/crm/commerce/subscription-replace-postgres.integration.spec.ts src/crm/commerce/subscription-cancel-postgres.integration.spec.ts src/crm/commerce/subscription-lesson-race-postgres.integration.spec.ts
npm run typecheck
repowise update --index-only
git add server/src/crm/commerce/subscription-lifecycle-boundaries.spec.ts server/src/crm/commerce/subscription-lifecycle-command.policy.ts server/src/crm/commerce/subscription-replacement.policy.ts server/src/crm/commerce/subscription-cancellation.policy.ts server/src/crm/commerce/subscription-replacement.service.ts server/src/crm/commerce/subscription-cancellation.service.ts server/src/crm/commerce/subscription-lifecycle.service.ts server/src/crm/crm.module.ts
git commit -m "test(commerce): guard lifecycle ownership boundaries"
~~~

Between the RepoWise update and commit, query targeted health/risk and run Sentrux rescan/health/rules plus `git diff --check`.

### Task 7: Package 9 full evidence and recovery ledger

**Files:**
- Modify: docs/superpowers/specs/2026-08-25-production-code-health-recovery-design.md
- Modify: docs/superpowers/plans/2026-08-26-subscription-lifecycle-semantic-split.md
- Generate ignored evidence: .superpowers/sdd/2026-08-26-subscription-lifecycle-semantic-split/task-7-report.md

**Interfaces:**
- Consumes: final Package 9 commit range, server coverage/lcov.info, RepoWise/Sentrux output.
- Produces: exact Package 9 acceptance record and Package 10 reranking.

- [ ] **Step 1: Run the full backend verification**

From server:

~~~bash
npm test
npm run typecheck
npm run build
npm test -- --coverage --coverageReporters=lcov
~~~

Expected: all backend tests pass twice, typecheck/build exit zero, and server/coverage/lcov.info is generated.

- [ ] **Step 2: Ingest truthful coverage and refresh RepoWise**

From repository root:

~~~bash
repowise coverage add server/coverage/lcov.info
repowise update --index-only
~~~

Record exact coverage SHA, file count, target line/branch coverage, and any uncovered changed lines. Do not rename tests or source files for pairing.

- [ ] **Step 3: Run RepoWise package gates**

Query target health for the old facade and all five replacement owners, repository dashboard/module scores, changed-file risk, full-range change risk, consumers/cycles/conformance, and production god count.

Accept only when:

~~~text
production god_class count: 25 -> 24
subscription-lifecycle.service.ts: no god_class/brain_method
each new structural owner: max CCN <= 10
facade: <= 110 physical non-comment lines and transaction-free
RepoWise consumers/cycles/conformance: no new violation
~~~

If a new owner has health below 7.0, document every deduction and rework any current structural defect before accepting history/co-change-only residue.

- [ ] **Step 4: Run Sentrux package gates**

~~~text
rescan current repository
quality >= 5736
depth <= 13
acyclicity raw 0 / score 10000
rules 2/2
~~~

Any root-cause regression blocks acceptance even if aggregate quality rises.

- [ ] **Step 5: Update exact evidence**

Append a Package 9 verified outcome to the master spec and a Results section to this plan. Include commits, commands, pass counts/durations, coverage SHA, old/new health/NLOC/CCN/deficit, portfolio delta, production god count, Sentrux root causes, RepoWise risk, accepted exceptions, and the freshly reranked Package 10 owner.

- [ ] **Step 6: Verify docs and commit**

~~~bash
git diff --check
git status --short
git add docs/superpowers/specs/2026-08-25-production-code-health-recovery-design.md docs/superpowers/plans/2026-08-26-subscription-lifecycle-semantic-split.md
git commit -m "docs(health): record lifecycle split evidence"
repowise update --index-only
~~~

Expected: worktree clean, RepoWise exact at final HEAD, and no production/test file is included in the evidence commit.

## Execution Handoff

Package 9 is complete only after every task-specific review is clean, the final whole-package review is clean, and Task 7 records exact evidence. Continuous execution then reranks and starts Package 10 under the approved 25 -> 0 master program.
