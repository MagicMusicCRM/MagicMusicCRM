# Leads Service Semantic Split

## Context

`server/src/crm/leads.service.ts` is the next production-first god-class
target: RepoWise health `1.90`, `1,376` NLOC, max CCN `26`, weighted deficit
`8,394`, four bug fixes in six months, 35 co-change partners, and change
entropy in percentile `98.3`. The class mixes board SQL and pagination, card
aggregation, directory/history reads, transactional writes, mapping, audit,
realtime publication, and compatibility policy.

The file is guarded by four coverage-backed suites (`43/43` baseline tests)
and is named by the export-surface contract. The public `LeadsService` symbol
therefore remains as a narrow application facade; its implementation logic and
SQL do not remain in the facade.

## Decision

Split the current owner into these semantic boundaries:

- `lead-board.service.ts` owns board query orchestration and SQL.
- `lead-board-filter.ts` owns parameterized board predicates and cursor policy.
- `lead-board-assembler.ts` owns pure pipeline-column assembly, per-column
  pagination, sorting, counts, and the deprecated scalar cursor projection.
- `lead-card.service.ts` owns one-card aggregation and related-record reads.
- `lead-directory.service.ts` owns list, status-history, and application reads.
- `lead-command.service.ts` owns authorization, command publication, audit,
  realtime events, manual linking, and the deletion prohibition.
- `lead-write.repository.ts` owns transactional create/update persistence,
  status resolution, eligible-responsible mirrors, typed fields, and status
  history.
- `lead-model.ts` owns shared row contracts and pure DTO mapping.

`LeadsService` delegates its existing public methods to board, card, directory,
and command owners. Controllers, routes, DTOs, response shapes, and public
NestJS behavior remain unchanged.

## Preserved invariants

- CRM authorization remains before every read or mutation; application reads
  keep their existing operational-data permission.
- Build 144 keeps an independent keyset cursor per status column, microsecond
  timestamp fidelity, per-partition look-ahead, and oldest/newest ordering.
- Frozen build 143 keeps the unscoped scalar cursor only for the current
  compatibility window; new clients do not consume it.
- Lead update and status/owner history remain one transaction with a locked
  pre-image. Reason snapshots, source snapshot, branch, and actor are retained.
- Status accepts a valid UUID, a unique stage key/name, or unresolved legacy
  input that preserves the current value. Clear-status remains explicit.
- Responsible assignment remains eligibility-checked and mirrored into custom
  data. Automatic claiming is best-effort and never overwrites a current owner.
- Typed custom fields remain in the same create/update transaction. Audit diffs
  retain canonical fields and definition IDs.
- Manual student linking rejects missing entities and conflicting ownership,
  then audits and publishes exactly once.
- Direct lead deletion remains blocked; no production data, schema, migration,
  API, or response contract changes in this package.

## Acceptance

- `leads.service.ts` contains no SQL or domain branching and remains below 120
  NLOC as the stable application facade.
- Every new production owner has RepoWise health at least `7.0`, max CCN at
  most `10`, at most `500` NLOC, and no god/brain finding.
- Combined replacement weighted deficit is at most `1,678`, an 80% reduction
  from the `8,394` baseline.
- Coverage-backed tests, focused lead tests, full backend tests, typecheck,
  Nest build, formatting, and `git diff --check` pass.
- RepoWise is exact at implementation HEAD and reports no broken consumer,
  missing test, conformance violation, or dependency cycle.
- Sentrux is scanned after each structural step; acyclicity remains `10000`,
  depth remains at most `13`, both architecture rules pass, and any quality
  variance is explained by the root-cause dimensions rather than hidden.

## Rollback

Land model/filter/assembler, each read owner, write ownership, and facade wiring
as separate commits. Revert in reverse order. No database or production-state
rollback is required because the package preserves all persistence contracts.

## Verified outcome

The semantic split is implemented and verified at `1ee213707149` as eight
independently revertible implementation, correction, and test-ownership
commits. `LeadsService` remains the stable NestJS application port but now has
only `63` NLOC, max CCN `1`, and no SQL, transaction, mapping, or domain branch.

- RepoWise is exact with `index_behind=false`. The eight new production owners
  score `7.44–9.65`, max CCN is `8`, max NLOC is `346`, and none has a god/brain
  finding. Including the historically co-changed facade, combined weighted
  deficit is `247` versus `8,394`, a `97.1%` reduction.
- The facade score is `5.44` solely because its retained public filename still
  carries co-change history with 32 files; its current maintainability score is
  `7.60`, max CCN is `1`, and structural tests enforce the SQL-free `120`-NLOC
  ceiling. Replacing the public port would discard compatibility without
  reducing current code risk.
- The code HEAD passed all `211` backend suites and `1,537` tests, typecheck,
  Nest build, and diff checks. The final test-only commits add eight direct
  semantic-owner tests; all nine focused owner suites pass `36/36`. RepoWise
  now reports `missing_tests=[]`, no cycle, no conformance violation, no broken
  consumer, and no breaking API change.
- Change risk is `Elevated`, percentile `100`, because the ownership move spans
  22 TypeScript files and `3,836` changed lines. Four coverage-backed suites
  guard the external surface, `untested_changes` is empty, and the complete
  backend suite was therefore used as the authoritative behavior gate.
- Sentrux improved from package baseline `5730` to `5745`: acyclicity `10000`
  with raw `0`, depth `13`, equality `6249`, modularity `5369`, redundancy
  `4896`, and both architecture rules passing.

Backend module health is now `7.02`, crossing the program target of `7.0`.
Repository code-only health moved from `6.21` to `6.26`; the overall `7.5`
contract and Flutter `7.0` contract remain open.
