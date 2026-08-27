# Tier 3 Lane I — Subscription Issue UI

Status: ACCEPTED AFTER INTEGRATION HARDENING

- Base: `37667c097e850092dbafaa0480c5e4b64e623025`
- Final commit: `f3282da96b2ff1a3acd653ff6ec84703d0002618`
- Subject: `refactor(commerce-ui): split subscription issue form owners`
- RED: focused controller test exited 1 because controller/models imports did
  not exist.
- Original lane smoke: 16/16 PASS. Final Lane I smoke after review hardening:
  21/21 PASS; integrated Tier 3 smoke: 48/48 PASS.
- Analyze: six production owners, no issues.
- Format: nine source/test files, zero changes.
- Diff: `git diff --check` PASS; all five verify-only paths unchanged.
- Exact index: RepoWise `last_sync_commit` equals final commit.

Final exact-HEAD health rows (raw score / NLOC / max CCN):

- shell 4.48 / 135 / 6 (maintainability 8.80; the remaining headline penalty
  is history/evolution, not current god/brain structure)
- models 8.09 / 130 / 4 (includes visible no-coverage penalty 1.56)
- pricing 8.20 / 199 / 10
- controller 9.55 / 247 / 7
- form view 8.10 / 404 / 6
- components 9.35 / 417 / 7

Coverage provenance: `coverage=null`, `test_map=null`; fresh coverage is
deferred to Campaign global gate. No new owner has a god-class or brain-method
marker.

Behavior proof: PostgreSQL half-up/two-decimal percent, fixed/surcharge/foreign
payer validation, positive 2..12 UTC month-clamped installments with first-item
remainder, preview-before-commit, insufficient-balance no-commit, identity
rotation before attempt, freeze after attempt, and exact retry identity/input.
Review hardening additionally proves stale preview success/error cannot replace a
newer draft, percent→fixed remounts an empty value field, and malformed/zero/
over-base amounts render `Итого: Не указано` instead of a misleading total.
