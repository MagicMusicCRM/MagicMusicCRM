# Leads Service Semantic Split Implementation Plan

**Goal:** Remove the `LeadsService` god class while preserving its stable
application surface and all lead read/write contracts.

**Architecture:** Keep `LeadsService` as a thin injected facade. Move board,
card, directory, and command behavior to semantic services; isolate pure board
filter/assembly and transactional persistence from orchestration.

## 1. Lock the ownership contract

- Add a structural test requiring every semantic owner and rejecting SQL or
  domain logic in the final facade.
- Run it red, then keep the four RepoWise coverage-backed suites green after
  each extraction.

## 2. Extract pure board policy

- Move shared lead row contracts and DTO mapping to `lead-model.ts`.
- Move cursor/filter construction to `lead-board-filter.ts` and column/page
  assembly to `lead-board-assembler.ts`.
- Add focused unit characterization for invalid cursor, scoped ordering,
  unassigned columns, independent partition cursors, and build-143 projection.
- Run focused tests, typecheck, Sentrux scan/rules, then commit.

## 3. Extract read owners

- Move board SQL/orchestration to `LeadBoardService`.
- Move card aggregation and related reads to `LeadCardService`.
- Move list/history/application queries to `LeadDirectoryService`.
- Delegate from the facade after each move; run focused tests and Sentrux after
  every structural commit.

## 4. Extract transactional writes

- Move create/update transactions and status resolution into
  `LeadWriteRepository`.
- Move command authorization, audit, realtime, linking, and deletion policy to
  `LeadCommandService`.
- Preserve lock, transition, typed-field, history, responsible, audit, and
  publication ordering. Run command tests plus the PostgreSQL integration gate.

## 5. Close the facade and verify

- Register every owner in `CrmModule`; keep controller and export surface on
  `LeadsService`.
- Require the facade to be delegation-only and below 120 NLOC.
- Refresh RepoWise, record per-file health/change risk, run Sentrux/rules, all
  focused tests, full backend tests, typecheck, build, and diff checks.
- Record the measured outcome in this package spec and the global recovery
  design, then re-rank the next production god class.
