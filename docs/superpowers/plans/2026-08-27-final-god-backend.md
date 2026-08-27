# Final God Files Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three remaining backend god services with thin compatibility facades and focused injectable owners.

**Architecture:** Finance splits by payment/query/transfer/expense capability; lesson commands split by preview/write/planned-settlement transaction; funnel splits by query/transition/revision around shared repository/resolver owners. Controllers and HTTP contracts remain untouched, and one integrator wires all providers in `CrmModule`.

**Tech Stack:** NestJS, TypeScript, PostgreSQL, Jest, RepoWise, Sentrux

**Spec:** `docs/superpowers/specs/2026-08-27-final-god-files-zero-design.md`

## Global Constraints

- Preserve all public facade signatures, DTOs, routes, error codes and JSON shapes.
- Preserve RBAC, transactions, expected version, idempotency, audit, outbox, locks and append-only history exactly.
- Lane agents must not edit `server/src/crm/crm.module.ts`; the integrator owns it.
- New owners: health `>=7.0`, max CCN `<=10`, NLOC `<=350`; facade NLOC target `<=150`.
- Run lane smoke only; the full backend gate runs once after all lanes integrate.

---

### Task 1: Finance capability owners

**Files:**
- Create: `server/src/crm/finance/finance-payment.service.ts`
- Create: `server/src/crm/finance/student-finance-query.service.ts`
- Create: `server/src/crm/finance/student-account-transfer.service.ts`
- Create: `server/src/crm/finance/expense.service.ts`
- Create: `server/src/crm/finance/finance.types.ts`
- Create: `server/src/crm/finance-service-boundary.spec.ts`
- Modify: `server/src/crm/finance.service.ts`
- Test: `server/src/crm/finance.service.spec.ts`
- Test: `server/src/crm/finance-balance-postgres.integration.spec.ts`

**Interfaces:**
- `FinancePaymentService`: `listRecentPaymentsForStudents`, `listPayments`, `createPayment` with the exact existing parameter/return inference.
- `StudentFinanceQueryService`: `listExpectedPayments`, `listStudentBalances`, `listStudentLedger`.
- `StudentAccountTransferService`: `createAccountTransfer`.
- `ExpenseService`: `listExpenses`, `createExpense`, `updateExpense`, `deleteExpense`.
- `FinanceService` injects these four owners as `private readonly` and delegates one-to-one.

- [ ] **Step 1: Freeze the boundary with a failing AST test**

Assert the facade exports the same ten public methods, injects exactly the four
owners, contains no SQL/transaction/audit/realtime implementation, and every
owner is injectable and below the architecture budgets. Add assertions that
expense deletion remains a soft-delete and transfer/payment transaction calls
remain in their respective command owners.

- [ ] **Step 2: Run RED**

```powershell
cd server
npm test -- --runTestsByPath src/crm/finance-service-boundary.spec.ts
```

Expected: FAIL because the capability owners do not exist.

- [ ] **Step 3: Move code without semantic edits**

Move existing private row types/mappers beside their consuming owner. Preserve
SQL byte-for-byte where practical. Construct the facade in this form:

```ts
@Injectable()
export class FinanceService {
  constructor(
    private readonly payments: FinancePaymentService,
    private readonly queries: StudentFinanceQueryService,
    private readonly transfers: StudentAccountTransferService,
    private readonly expenses: ExpenseService,
  ) {}
}
```

Each public method returns the exact delegate call; do not add catch/rethrow,
new validation, or cross-owner transactions.

- [ ] **Step 4: Run Finance smoke**

```powershell
npm test -- --runTestsByPath src/crm/finance.service.spec.ts src/crm/finance-balance-postgres.integration.spec.ts src/analytics/v4-reporting-scope-postgres.integration.spec.ts src/crm/finance-service-boundary.spec.ts
npm run typecheck
git diff --check
```

Expected: all selected suites PASS, typecheck PASS, diff check empty.

- [ ] **Step 5: Commit the lane**

```powershell
git add server/src/crm/finance.service.ts server/src/crm/finance server/src/crm/finance-service-boundary.spec.ts server/src/crm/finance.service.spec.ts server/src/crm/finance-balance-postgres.integration.spec.ts
git commit -m "refactor(finance): split capability services"
```

### Task 2: Student funnel owners

**Files:**
- Create: `server/src/crm/student-funnel/student-funnel.types.ts`
- Create: `server/src/crm/student-funnel/student-funnel.definition.ts`
- Create: `server/src/crm/student-funnel/student-funnel.repository.ts`
- Create: `server/src/crm/student-funnel/student-funnel-resolver.service.ts`
- Create: `server/src/crm/student-funnel/student-funnel-query.service.ts`
- Create: `server/src/crm/student-funnel/student-funnel-transition.policy.ts`
- Create: `server/src/crm/student-funnel/student-funnel-revision.service.ts`
- Create: `server/src/crm/student-funnel-boundary.spec.ts`
- Modify: `server/src/crm/student-funnel.service.ts`
- Test: `server/src/crm/student-funnel-postgres.integration.spec.ts`

**Interfaces:**
- Query owner: `getEffective(actor, branchId?, clientType?)`, `listRevisions(actor, query)`.
- Revision owner: `preview(actor, dto)`, `publish(actor, dto)`, `rollback(actor, dto)`.
- Transition policy: `assertCreateStatus`, `assertTransition`, `assertLeadTransition`.
- Compatibility file re-exports existing public types and delegates all eight public methods.

- [ ] **Step 1: Freeze append-only and facade contracts**

Add an AST/source boundary test that rejects `UPDATE`/`DELETE` against funnel
revision history, requires transaction/advisory-lock/sync ownership in the
revision service, verifies exact facade DI and public signatures, and prevents
query/policy owners from importing Audit/Realtime mutation dependencies.

- [ ] **Step 2: Run RED**

```powershell
cd server
npm test -- --runTestsByPath src/crm/student-funnel-boundary.spec.ts
```

Expected: FAIL on missing owners.

- [ ] **Step 3: Extract repository, resolver, policy, query and revision owners**

Keep stage normalization/stable-key/diff/apply-patch as pure definition
functions. Repository owns SQL row loading/counting/remediation. Resolver owns
school/branch fallback. Revision service keeps the complete transaction and
post-commit audit/realtime sequence. The facade contains delegation only.

- [ ] **Step 4: Run funnel smoke**

```powershell
npm test -- --runTestsByPath src/crm/student-funnel-postgres.integration.spec.ts src/crm/students/student-mutation.executor.spec.ts src/crm/student-funnel-boundary.spec.ts
npm run typecheck
git diff --check
```

Expected: all selected suites PASS and immutable history assertions remain green.

- [ ] **Step 5: Commit the lane**

```powershell
git add server/src/crm/student-funnel.service.ts server/src/crm/student-funnel server/src/crm/student-funnel-boundary.spec.ts server/src/crm/student-funnel-postgres.integration.spec.ts
git commit -m "refactor(funnel): split revision and policy owners"
```

### Task 3: Lesson command transaction owners

**Files:**
- Create: `server/src/crm/schedule/lesson-command.repository.ts`
- Create: `server/src/crm/schedule/lesson-constraint-preview.service.ts`
- Create: `server/src/crm/schedule/lesson-write-command.service.ts`
- Create: `server/src/crm/schedule/lesson-planned-settlement-command.service.ts`
- Create: `server/src/crm/schedule/lesson-command-integrity.ts`
- Create: `server/src/crm/schedule/lesson-command-boundary.spec.ts`
- Modify: `server/src/crm/schedule/lesson-command.service.ts`
- Test: `server/src/crm/schedule/lesson-command.service.spec.ts`
- Test: `server/src/crm/schedule/lesson-write-parity.integration.spec.ts`

**Interfaces:**
- Preview owner: `previewConstraints(actor, dto)`.
- Write owner: `create(actor, dto, metadata)`, `update(actor, lessonId, dto, metadata)`.
- Settlement owner: `previewSettlementPlan(actor, lessonId, dto)`, `updateSettlementPlan(actor, lessonId, dto, metadata)`.
- Facade re-exports `LessonCommandMetadata` and delegates these five methods.

- [ ] **Step 1: Freeze transaction and metadata topology**

Add a boundary test requiring exact facade delegation/private-readonly DI,
exactly three `executeVersionedMutation` calls across the two command owners,
no transaction/SQL in the facade, the neutral metadata import/re-export, and
the existing audit/outbox operation names.

- [ ] **Step 2: Run RED**

```powershell
cd server
npm test -- --runTestsByPath src/crm/schedule/lesson-command-boundary.spec.ts src/crm/schedule/lesson-command-metadata.spec.ts
```

Expected: boundary suite FAIL on missing owners; metadata suite remains PASS.

- [ ] **Step 3: Move complete transaction envelopes**

Move create/update envelopes together into the write owner and planned
settlement preview/update together into the settlement owner. Never split a
savepoint, lock acquisition, mutation callback, settlement or response
projection across injectable owners. Repository receives the current
`Queryable`/`PoolClient` explicitly and performs no transaction creation.

- [ ] **Step 4: Run lesson smoke**

```powershell
npm test -- --runTestsByPath src/crm/schedule/lesson-command.service.spec.ts src/crm/schedule/lesson-command-metadata.spec.ts src/crm/schedule/lesson-write-parity.integration.spec.ts src/crm/schedule/lesson-command-boundary.spec.ts
npm run typecheck
git diff --check
```

Expected: all selected suites PASS, including replay/expected-version parity.

- [ ] **Step 5: Commit the lane**

```powershell
git add server/src/crm/schedule/lesson-command.service.ts server/src/crm/schedule/lesson-command.repository.ts server/src/crm/schedule/lesson-constraint-preview.service.ts server/src/crm/schedule/lesson-write-command.service.ts server/src/crm/schedule/lesson-planned-settlement-command.service.ts server/src/crm/schedule/lesson-command-integrity.ts server/src/crm/schedule/lesson-command-boundary.spec.ts server/src/crm/schedule/lesson-command.service.spec.ts server/src/crm/schedule/lesson-write-parity.integration.spec.ts
git commit -m "refactor(schedule): split lesson command owners"
```

### Task 4: Integrate Nest providers and measure the wave

**Files:**
- Modify: `server/src/crm/crm.module.ts`
- Modify: `server/src/crm/campaign12-contract-modules.spec.ts`

**Interfaces:** All new owners are internal module providers; only the three compatibility facades retain their existing export/caller topology.

- [ ] **Step 1: Register owners immediately before each facade**

Import every new injectable owner and add it to `providers`. Do not add any of
them to `exports`. Keep the three facades in their existing provider/export
positions so controller constructor tokens remain unchanged.

- [ ] **Step 2: Add module privacy assertions and run wave smoke**

```powershell
cd server
npm test -- --runTestsByPath src/crm/campaign12-contract-modules.spec.ts src/crm/finance-service-boundary.spec.ts src/crm/student-funnel-boundary.spec.ts src/crm/schedule/lesson-command-boundary.spec.ts
npm run typecheck
npm run build
```

Expected: providers resolve, extracted owners are private, all tests/typecheck/build PASS.

- [ ] **Step 3: Commit integration and refresh metrics**

```powershell
git add server/src/crm/crm.module.ts server/src/crm/campaign12-contract-modules.spec.ts
git commit -m "refactor(crm): wire final backend owners"
repowise update --index-only
sentrux check
```

Expected: the three backend god/brain findings disappear; no new owner violates health/CCN/NLOC gates; Sentrux rules remain 2/2.
