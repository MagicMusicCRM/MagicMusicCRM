# v7 T4.1.3 — Client Card Recurring Plans

**Date:** 2026-08-07
**Scope:** `REQ-SCHEDULE-102` / `T4.1.3`

## Result

The canonical Student card now renders one recurring-plan section immediately
after preferred schedule. Active plans are expanded, ended plans are collapsed,
and each plan owns a bounded two-row lesson tray with cursor arrows. An absent
preferred schedule does not hide plans or actual fallback lessons.

The implementation reuses the existing v7 adaptive surfaces and
`PreferredScheduleEditor`; no second form system or dependency was introduced.
Individual plan create, effective edit and end all call the versioned/idempotent
Plan aggregate from `T4.1.1–T4.1.2`. Group plans are read through participant
membership and retain backend-owned participants during edits.

## Contracts verified

- Plan DTOs expose active/ended state, effective rows, teacher/room/branch labels,
  participant-safe group visibility and tray cursor state.
- Create requires an active subscription; open-ended plans are explicit.
- End requires a staff-visible reason, impact preview and the same retained
  mutation identity for commit/retry.
- The tray shows authoritative lifecycle, settlement and relation markers; it
  opens the existing Lesson surface instead of duplicating Lesson actions.
- Roles without schedule-read capability do not mount the series/plan providers
  and issue no hidden schedule requests.
- The existing account balance test now asserts the confirmed reservation rule:
  `5 paid - 2 used - 1 reserved = 2 available`.

## Verification

| Gate | Result |
|---|---|
| Responsive widget tests | PASS — 6/6 at 360/840/1200 and text scale 1.25 |
| Client workspace + preferred schedule regression | PASS — 21/21 targeted |
| Flutter analyze | PASS — no issues |
| Flutter full | PASS — 632/632 |
| Schedule Plan PostgreSQL | PASS — 6/6 |
| Backend typecheck/build | PASS |
| Backend full | PASS — 155/155 suites, 1223/1223 tests |
| Access coverage | PASS — 297/297 routes, unexplained allow 0 |
| Shadow compare | PASS — access 1782, schedule 2000, unexplained 0 |
| v7 reconciliation | PASS — `issues=[]` |
| Inventory stale checks | PASS — v4/v6/v7 |

Inventory after the change: backend routes 309, DTO fields 776, production
reachable Dart files 258/259, production wire calls 267/267, unknown Lesson
mutation callers 0 and unowned items 0.
