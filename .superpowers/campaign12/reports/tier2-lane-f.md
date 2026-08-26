# Campaign-12 Tier 2 — Lane F evidence

- Base: `2c08eab6cce223b7a5ca2dc56b1455cfbd098ef8`
- Commit: `bb88b9e96097c57c49cd07e20259ae120c0aa781`
- Subject: `refactor(schedule): split lesson transition workflows`
- Branch: `codex/campaign12-lesson-transition`
- Status: PASS — fresh coverage deferred to the Campaign-12 global gate.

## Ownership result

The former `LessonTransitionService` god owner (baseline health 4.58, 1,535 NLOC,
max CCN 36, weighted deficit 5,250) is now an 86-NLOC compatibility facade
with exactly eight direct delegations. Persistence and orchestration are owned by:

| Owner | Raw health | Tier score | NLOC | Max CCN |
| --- | ---: | ---: | ---: | ---: |
| `lesson-transition.service.ts` | 6.65 | 8.21* | 86 | 1 |
| `lesson-transition-preparation.service.ts` | 5.64 | 7.20* | 436 | 8 |
| `lesson-transition-financial.service.ts` | 7.79 | 7.79 | 159 | 4 |
| `lesson-transition-commit.service.ts` | 7.06 | 7.06 | 331 | 8 |
| `lesson-transition-preview.service.ts` | 9.30 | 9.30 | 80 | 3 |
| `lesson-transition-command.service.ts` | 8.23 | 8.23 | 162 | 8 |
| `lesson-bulk-transition.service.ts` | 8.58 | 8.58 | 210 | 7 |

`*` RepoWise reports `has_test_file=false` and no ingested LCOV for the new
owners. The established tier policy preserves the raw score and removes only
the stale `untested_hotspot` penalty (`+1.56`) where it masks the threshold.
Fresh LCOV must remove that exception in Task M; every final raw score must be
at least 7.0.

RepoWise index evidence:

- `repowise update --index-only`: PASS, 31 changed files, 13,960 nodes,
  33,894 edges, elapsed 2m37s.
- `repowise status --format json`: `last_sync_commit` exactly
  `bb88b9e96097c57c49cd07e20259ae120c0aa781`.
- One module health pass selected all seven literal owner paths; every max CCN
  is at most 8 and every tier score is at least 7.0.

## Verification

- Metadata/boundary suites: 2 suites, 8/8 PASS; final Jest time 17.875s.
- Selected PostgreSQL cases: 3/3 PASS, 5 skipped by name filter; Jest time
  26.188s. Cases: `dry-runs the exact facts`,
  `rejects stale/tampered previews`, `commits a signed bulk transition`.
- `npm run typecheck -- --pretty false`: PASS.
- `git diff --check`: PASS.
- Verify-only controller, transition DTO, platform integrity, lifecycle,
  reservation, settlement, preview-token, and constraint-engine sources:
  unchanged from the accepted base.
- Final worktree status: clean.

## Preserved invariants

- Preview owns one transaction and exact savepoint / rollback / release order.
- Bulk owns one transaction; command and bulk each own one versioned mutation.
- Source row lock and settlement review precede sorted, unique advisory locks;
  constraint validation precedes coverage lock and successor insert.
- Source settlement and append-only completed correction precede fingerprint
  comparison; successor allocation and lifecycle append retain baseline order.
- Single commands retain `schedule.lesson.{operation}`, aggregate
  `schedule:lesson`, DTO expected version, audit/outbox payloads, idempotency,
  and source-then-successor post-commit publication.
- Bulk retains `schedule.lesson.bulk-transition`, aggregate
  `schedule:lesson-bulk`, expected version 0, deterministic lesson-id order,
  duplicate rejection, maximum 500, stale-fingerprint rollback, audit/outbox,
  and publication only after mutation resolution.

## Neutral command metadata

`lesson-command-metadata.ts` contains exactly two required fields:
`idempotencyKey` and `requestId`. Direct neutral imports are present in all five
consumers: lesson command, lesson series command, settlement correction, lesson
transition facade, and schedule plan. `lesson-command.service.ts` re-exports the
type from the historical path. Each service retains its existing validator and
error body.
