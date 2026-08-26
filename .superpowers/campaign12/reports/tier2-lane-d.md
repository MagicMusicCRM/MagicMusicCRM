# Tier 2 Lane D — Profile semantic owners

Campaign baseline: `2c08eab6cce223b7a5ca2dc56b1455cfbd098ef8`

Lane commit: `e57ad45fad6212e206ac1aa48948e6777dd4c1ef`

## Implemented boundary

- `ProfileService` is now a 36-NLOC compatibility facade with exactly three private readonly owners and the original seven public methods.
- `ProfileRecordRepository` owns profile reads, ensure-once persistence, and the three row projections.
- `MyProfileService`, `ProfileDirectoryService`, and `ProfileNotesService` own self-profile, directory/link projection, and note workflows respectively.
- `ProfileModule.exports` remains exactly `[ProfileService]`; all four new owners are private providers.
- The permanent TypeScript AST guard enforces exact constructor types/modifiers, method/owner/argument mappings, persistence-free facade, private module wiring, and 500-NLOC owner ceilings.

## Preserved behavior

- The SQL template multiset is byte-for-byte equivalent after newline normalization: 11 baseline templates, 11 extracted templates, 0 missing, 0 added.
- Missing self profiles are ensured once and reloaded; oldest branch assignment remains `homeBranchId`.
- Avatar lookup remains actor-owned, `profile_avatar`-scoped, active-only, and fail-closed.
- Client completion calls only `autoCreateLeadFromChat(actor, actor.userId, "onboarding")`; non-client completion calls only phone linking; incomplete profiles call neither.
- Directory/list/link/note RBAC calls, actor-scoped system-admin visibility, limits/order, student/lead-only projection, null-name fallback, trim validation, audit payloads, and audit-after-write order are unchanged.

## TDD and lane smoke

- RED: the three-owner command exited 1 with 3 failed suites and 0 tests because `my-profile.service`, `profile-directory.service`, and `profile-notes.service` did not exist; Jest time 13.896 s.
- First GREEN: 3 suites / 15 tests passed after a compile-only `ProfileRow` query generic correction; Jest time 14.983 s.
- Final exact smoke: 6 suites / 23 tests passed, 0 failed; Jest time 17.325 s.
- `npm run typecheck -- --pretty false` — PASS, `tsc --noEmit` exit 0.
- `git diff --check` and staged `git diff --cached --check` — PASS, exit 0; Git emitted only LF-to-CRLF working-copy notices.

## RepoWise evidence

The exact-SHA `repowise update --index-only` and health extraction were serialized with `Global\MagicMusicCRM-Campaign12-RepoWise`. `repowise status --format json` reported `last_sync_commit=e57ad45fad6212e206ac1aa48948e6777dd4c1ef` before accepted health extraction.

`repowise health --module profile --format json` returned an empty metrics array and was not accepted. The supported fallback ran one full health analysis and extracted exactly the five literal Profile paths.

Weighted deficit is `round(max(0, 8.0 - raw health) * NLOC)`.

| Production file | Raw health | Stale coverage penalty | NLOC | Max CCN | Weighted deficit | god/brain |
|---|---:|---:|---:|---:|---:|---|
| `server/src/profile/profile.service.ts` | 6.94 | 0.00 | 36 | 1 | 38 | none |
| `server/src/profile/profile-record.repository.ts` | 7.49 | 1.56 | 195 | 2 | 99 | none |
| `server/src/profile/my-profile.service.ts` | 8.63 | 0.00 | 155 | 10 | 0 | none |
| `server/src/profile/profile-directory.service.ts` | 9.85 | 0.00 | 356 | 2 | 0 | none |
| `server/src/profile/profile-notes.service.ts` | 9.65 | 0.00 | 94 | 3 | 0 | none |

All four new owners satisfy raw health `>=7.0`, max CCN `<=10`, and no god/brain finding. The facade's 6.94 is historical/churn/duplication drag on the pre-existing path; its live structure is independently guarded at 36 NLOC and CCN 1. Combined replacement weighted deficit is 137 versus baseline 3,424, a 96.0% reduction.

## Commit

`refactor(profile): split profile service semantic owners`
