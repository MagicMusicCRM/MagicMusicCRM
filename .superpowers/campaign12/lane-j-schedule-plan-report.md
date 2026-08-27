# Campaign-12 Lane J — Schedule plan workflows

- Tier 4 base: `624f36c560ed7fb2de5f92612c3a9b2445339d68`
- Intended commit: `refactor(schedule): split schedule plan workflows`
- Production target: `server/src/crm/schedule/schedule-plan.service.ts`

## Before / after

| Owner | Before NLOC / max CCN / health | After static NLOC / max CCN |
|---|---:|---:|
| `schedule-plan.service.ts` | 1,148 / 19 / 1.90 | 74 / 1 |
| `schedule-plan-definition.service.ts` | — | 500 / 9 |
| `schedule-plan-overlap-analyzer.ts` | — | 141 / 4 |
| `schedule-plan-query.service.ts` | — | 176 / 9 |
| `schedule-plan-constraint-preview.service.ts` | — | 170 / 2 |
| `schedule-plan-mutation.service.ts` | — | 375 / 4 |
| `schedule-plan-end.service.ts` | — | 324 / 6 |

The permanent AST boundary suite calculates source NLOC and every callable's
cyclomatic complexity. It rejects any owner above 500 NLOC or CCN 10. The
root integrator owns the exact post-merge RepoWise update and targeted health
read, so this isolated lane did not mutate the shared index.

## Characterization and boundary evidence

- RED was observed before production extraction: Jest failed because the six
  required owner modules were absent.
- `schedule-plan-services.spec.ts` records sorted unique advisory locks,
  subscription `order by id for update`, exact update/end event order, keyset
  tray error codes and cursors, `1..40` clamping, previous-page reversal, and
  symmetric per-student overlap failures with rule `schedule_plan.rows`.
- `schedule-plan-boundaries.spec.ts` enforces the four-owner constructor,
  eight direct facade delegations, private Nest providers, unchanged CRM
  exports, transaction/versioned-mutation ownership, neutral
  `LessonCommandMetadata`, NLOC, and CCN limits.
- The PostgreSQL fixture now constructs the same real repository, lesson
  series, materializer, lifecycle, reservation, preview-token, settlement,
  constraint, and platform-integrity collaborators behind the facade.

## Preserved invariants

- Create/update still use aggregate `schedule:plan`, expected versions `0` and
  DTO version, deterministic IDs, idempotency key/request ID, audit actions
  `crm.schedule_plan_created` / `crm.schedule_plan_updated`, and outbox event
  `schedule.plan.changed`.
- Update retains plan/participant/resource/subscription/series lock ordering,
  inserts continuations before retiring old series, preserves participant
  history, then validates and materializes the new series.
- End retains the signed impact fingerprint, audit action
  `crm.schedule_plan_ended`, series locks before locked impact, stale-preview
  rejection, append-only lesson transitions, terminal lesson history, and
  reservation release.
- Controller, DTO, repository, types, series command, materializer, lifecycle,
  reservation, settlement, preview-token, and constraint-engine production
  files are unchanged.

## Focused lane gate

- Unit + AST boundary: 9 passed in 5.954 s.
- PostgreSQL selected cases: 4 passed, 5 skipped in 10.2 s:
  create open-ended plan, concurrent effective edit, stale end preview, bounded
  tray paging.
- Restricted TypeScript typecheck passed with zero errors; all 11 changed
  TypeScript files match Prettier 3.6.2; `git diff --check` passed. No global
  backend suite, coverage, RepoWise update, or Sentrux scan was run in this
  lane.
