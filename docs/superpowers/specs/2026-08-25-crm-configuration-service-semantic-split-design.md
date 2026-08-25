# CRM Configuration Service Semantic Split Design

**Date:** 2026-08-25

**Status:** Approved by the owner through the production code-health program

## Context

Fresh RepoWise analysis at `a2ce5af3a29f` identifies
`server/src/crm/crm-configuration.service.ts` as the next production health
directive. The file has health `1.06`, 1,444 NLOC, maximum CCN `53`, and a
weighted deficit of `10,021`. `CrmConfigurationService` spans 1,275 lines and
33 methods. Its two dominant brain methods are `normalizeSnapshot` (461 lines,
CCN `53`) and `buildImpact` (160 lines, CCN `27`). The file is a 92nd-percentile
churn hotspot with five dependents and no paired unit test.

The service currently owns four concerns: public configuration lifecycle,
snapshot parsing, change-impact policy, and persistence details. The existing
PostgreSQL integration suite verifies nine configuration/contract scenarios,
but the pure rules are reachable only through the full service and database.

The approved recovery program already selects the semantic boundary: move
snapshot normalization and impact calculation into pure policy components,
while leaving persistence orchestration in the canonical service.

## Goal

Remove the `CrmConfigurationService` god-class and brain-method findings by
extracting cohesive, directly tested configuration policies without changing
routes, DTOs, response shapes, SQL semantics, RBAC, transaction ownership,
advisory locks, optimistic versions, immutable revisions, audit, realtime
fanout, or stored configuration data.

This is package 3 of the production code-health recovery program. The global
program remains active after this package and immediately re-ranks the next
production god file.

## Considered approaches

### Semantic policy split — selected

Move contracts, snapshot normalization, branch inheritance, and impact policy
to dependency-light modules. Keep one service as the real lifecycle and
persistence owner. This removes the high-complexity responsibilities while
preserving the current public API and transaction boundary.

### Full controller-to-repository rewrite

Split every route into separate read, draft, publication, and repository
providers and inject them directly into the controller. This could make the
remaining service smaller, but it expands Nest composition and moves
transaction-sensitive behavior before the existing rules are independently
characterized. It is rejected for this package.

### Private method extraction only

Shorten the two brain methods inside the same class. This reduces method CCN
but leaves one owner responsible for policy, persistence, authorization, and
side effects. It is rejected because it does not remove the architectural
god-class boundary.

## Approved boundaries

### `crm-configuration.contracts.ts`

The existing dependency-free contract module becomes the single owner of:

- configuration category, field, option-set, setting, snapshot, branch-patch,
  and impact-report types;
- lesson-settlement and teacher-compensation catalog contracts;
- no Nest, database, service, or UI imports.

All production and test consumers import these types from the contract module.
`crm-configuration.service.ts` does not re-export compatibility aliases.

### `crm-configuration-snapshot-normalizer.ts`

Pure snapshot parsing and validation:

- normalize categories, fields, visibility, legacy entity copies, options,
  option sets, and business settings;
- normalize lesson-settlement and teacher-compensation catalogs;
- preserve all current Russian validation messages, field paths, error codes,
  limits, stable-key ordering, deduplication, and legacy merge behavior;
- expose one `normalizeCrmConfigurationSnapshot(raw)` entry point whose body
  composes focused parsers rather than containing the existing 461-line brain
  method.

The module may throw the existing `UnprocessableEntityException`, but performs
no I/O and owns no Nest provider or mutable state.

### `crm-configuration-branch.policy.ts`

Pure school/branch inheritance behavior:

- `createCrmConfigurationBranchPatch(school, desired)`;
- `applyCrmConfigurationBranchPatch(school, patch)`;
- `getCrmConfigurationSettingSources(snapshot, school)`.

The functions preserve sparse branch overrides and deep JSON equality for the
two commerce catalogs.

### `crm-configuration-impact.policy.ts`

Change safety and impact calculation:

- branch schema and non-overridable-setting blockers;
- stable commerce-key archival rules;
- system-field protection and stored-value type-migration blockers;
- field, setting, settlement, and compensation change counts;
- warnings and affected-screen projection.

The policy accepts a narrow async callback
`hasStoredClientFieldValues(definitionId): Promise<boolean>` for its only
persistence question. It does not import the database service or open a
transaction. Preview supplies a database-backed callback; publication supplies
one bound to its existing `PoolClient`, so atomic behavior is preserved.

### Remaining `CrmConfigurationService`

The canonical service continues to own:

- route-facing effective/draft/preview/publish/revision/rollback operations;
- scope checks and commerce capability authorization;
- effective school/branch revision reads;
- the publication transaction, advisory lock, expected-version check, draft
  deletion, immutable revision insert, and custom-field synchronization;
- post-commit audit and realtime fanout.

The controller continues injecting this one service. No facade, second
configuration model, generic repository framework, or new runtime provider is
introduced.

## Data flow

```text
CrmConfigurationController
  -> CrmConfigurationService
       -> normalizeCrmConfigurationSnapshot (pure)
       -> branch policy functions (pure)
       -> buildCrmConfigurationImpact (policy + narrow callback)
       -> DatabaseService / caller-owned PoolClient
       -> AuditService / RealtimeBus after commit
```

## Invariants

- School and branch versions remain independent and monotonically incremented.
- Branch configuration remains a sparse patch over the latest school snapshot.
- Publication keeps its advisory lock and all reads/writes inside the same
  transaction-owned executor.
- A stale base version fails before persistence.
- System fields cannot change type or become inactive; populated custom fields
  cannot change type without migration.
- Stable settlement and compensation keys are archived through `active=false`,
  not deleted or renamed.
- Only actors with `config.commerce.manage` may change commerce catalogs; the
  authorization check remains lock-aware for publication.
- Published revisions remain immutable; rollback creates a new revision.
- Existing Russian error messages, codes, fields, warnings, affected screens,
  API routes, status codes, and response payloads remain unchanged.

## Test strategy

Use strict red-green-refactor cycles. New unit tests exercise real pure policy
functions with hand-derived fixtures; mocks are limited to the one stored-value
lookup callback or external service boundaries.

- Snapshot tests cover legacy Lead/Student merge, option-set projection,
  duplicate/incompatible keys, field visibility, setting bounds, settlement
  contexts, compensation values, ordering, and active-item requirements.
- Branch tests cover sparse settings and commerce overrides, patch application,
  and source attribution.
- Impact tests cover every blocker family, stored-value migration, change
  counts, warnings, and affected screens.
- A paired `crm-configuration.service.spec.ts` covers observable lifecycle
  orchestration that does not require PostgreSQL; the existing PostgreSQL suite
  remains authoritative for SQL, transaction, version, rollback, and sync.
- Every structural commit runs focused tests, typecheck, `git diff --check`,
  Sentrux rescan/health/rules, and RepoWise index refresh.

## Acceptance

- `CrmConfigurationService` has no RepoWise god-class or brain-method finding,
  health is at least `7.0`, maximum CCN is at most `10`, and its production
  NLOC is at most `750`.
- Every extracted production file has health at least `7.0`; no extracted
  function is a critical large or complex method.
- Combined weighted deficit for the old service and its extracted owners is at
  most `2,000`, an 80% reduction from the `10,021` baseline.
- Focused policy/service tests, the PostgreSQL configuration suite, full
  backend tests, typecheck, Nest build, and `git diff --check` pass.
- Sentrux quality remains at least `4974`, acyclicity remains `1`, depth is at
  most `13`, and both architecture rules pass after each commit.
- RepoWise is indexed at implementation HEAD and reports no broken consumer or
  new dependency cycle.

If the semantic policy split leaves the service below health `7.0` or still
flagged as a god class, a separately tested follow-up cut may extract effective
revision persistence and field synchronization behind executor-preserving
functions. That cut is conditional on measured evidence, not speculative.

## Rollback

Contracts, snapshot normalization, branch policy, impact policy, and service
rewiring land as separate commits. Revert in reverse order. No database,
migration, production-state, or data-repair rollback is required.

## Verified implementation outcome

The package is implemented and verified at `650960b1940c`. RepoWise is exact
at that commit with `index_behind=false`.

- `CrmConfigurationService` improved from health `1.06`, `1,444` NLOC, max
  CCN `53`, and weighted deficit `10,021` to health `8.00`, `412` NLOC, max
  CCN `9`, and zero weighted deficit. The god-class finding is gone.
- Extracted production owners score: snapshot normalizer `8.15`, persistence
  `9.85`, impact policy `8.50`, branch policy `10.00`, and contracts `9.85`.
  Their combined weighted deficit with the facade is zero.
- Full backend verification passed: `204/204` suites, `1,516/1,516` tests,
  TypeScript typecheck, Nest build, and a clean diff. The focused CRM package
  passed `32/32` tests, including the PostgreSQL integration suite.
- Sentrux closed at quality `5720`, acyclicity raw `0` / score `10000` (no
  cycles), depth `13`, equality `6202`, modularity `5355`, redundancy `4841`,
  and both architecture rules passing.

Every package acceptance threshold passed. The conditional persistence cut
was evidence-triggered after the intermediate service remained at health
`6.44`; caller-owned `DatabaseService`/`PoolClient` execution was preserved,
and no schema, API, or product behavior changed.
