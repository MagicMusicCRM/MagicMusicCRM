# V6-503/504 — Unified, role-safe dashboard

**Дата:** 2026-08-04
**Статус:** PASS

## Production mounting

- Canonical staff destination `7` mounts one `ReportsWidget` through `MessengerScreen`.
- Separate production tabs `Отчёты`, `Финансы` and `Сводка` were replaced by one `Аналитика` dashboard.
- The unreachable legacy finance dashboard and legacy KPI card implementation were deleted.
- The production shell passes the current `CapabilitySnapshot` before any dashboard section/provider is built.

## Shared filter contract

- `DashboardFilter` is the single owner of inclusive calendar period and effective `branchId`.
- API normalization uses inclusive local start and exclusive next-day end for all applicable V4 sections and exports.
- Workspace state stores `dashboardFrom`, `dashboardTo` and `branchId`; direct-link focus may override the restored scope.
- Clients, lessons and school finance receive the identical normalized predicate. Shared-task counters are explicitly labelled as a current queue for which period/branch are not applicable.
- Status-card count and drilldown total are reconciled; unexplained mismatch becomes a visible section error instead of silently showing inconsistent data.

## Independent sections and access

| Section | Endpoint | Local state | Manager | Director/system_admin |
|---|---|---|---:|---:|
| Clients/funnel | `GET /analytics/v4/client-status/summary` | loading/error/retry | yes | yes |
| Lessons | `GET /analytics/v4/lesson-success` | loading/error/retry | yes | yes |
| Tasks | `GET /crm/shared-tasks?state=open&limit=1` | loading/error/retry | yes | yes |
| School finance | `GET /analytics/v4/school-finance` | loading/error/retry | absent/unrequested | capability-gated |

Client, Teacher and Admin direct dashboard attempts render an actor-safe forbidden state without report requests. A loaded capability snapshot overrides compatibility role helpers, so a Director label cannot create finance providers when the effective capability is absent.

## Verification

- `flutter analyze` — PASS, 0 issues.
- `flutter test --reporter compact` — PASS, **598/598**.
- Dashboard targeted suite — filter restore/direct-link, normalized query parity, partial failure, count/drilldown reconciliation, async export, responsive widths and capability-negative prefetch PASS.
- Backend `v4-reporting-scope-postgres` + actor payload-leak suites — **2/2 suites, 10/10 tests** PASS; Manager school-finance denial remains authoritative.
- `pwsh -NoProfile -File scripts/v6_ux_inventory.ps1 -Check` — PASS: routes=21, reachable=259, workspaceProduction=2, unowned=0.
- `git diff server/` — empty.
