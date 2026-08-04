# V6-601..605 / INT-S6 — Role workspaces and routed UX acceptance

**Дата:** 2026-08-04

**Статус:** ENGINEERING PASS; owner real-account UAT remains in V6-701

## Capability-projected role matrix

The active shell and its content guards use the current `CapabilitySnapshot`.
Role is a deny ceiling, so an over-privileged snapshot cannot mount a forbidden
persona surface.

| Persona | Mounted workspace | Explicit negative boundary | Scope |
|---|---|---|---|
| Client | own dashboard, next lesson and chat | no CRM shell and no foreign client route | self only |
| Teacher | Chat, assigned Day/Week schedule, assigned clients | no create/edit/drag/reschedule/cancel/attendance payload | assigned resources |
| Admin | Chat, Schedule, Clients | Tasks, Reports, Users, Config and school finance are absent and unrequested | actor-authorized branches |
| Manager | Overview, Chat, Schedule, Clients, Users, Tasks, Reports | school-wide finance is absent and unrequested | school default or selected branch, without school-finance capability |
| Director | full operational workspace, school finance, reports, access and CRM config | capability/resource deny remains fail-closed | school default plus sparse branch overrides |

Migration `0098_admin_persona_boundary` changes the active Admin package to
deny `workflow.task.read/write`. `HardInvariantPolicy` applies the same deny
after package and personal overrides, while route policy excludes Admin from
legacy and shared-task endpoints. Live `accessVersion` invalidation recreates
the shell and removes a destination in a second session.

## Client and Teacher top workflows

- Client route remains self-scoped; the dashboard exposes the next lesson and
  chat without a path into another client workspace.
- Teacher uses the assigned-only read model and Day/Week calendar. Drilldowns
  are actor-scoped, mutation controls are not mounted, and direct Lesson update
  returns `403` without changing the aggregate.
- Client calendar links preserve typed source context. App/system Back returns
  to the same date, mode and branch on Android and Windows.

Evidence: [Teacher calendar](v4-teacher-calendar-read-only.md),
[canonical client workspace](v6-canonical-client-workspace.md),
[client calendar](v6-client-calendar.md), and
[unified Back policy](v6-unified-back-policy.md).

## Admin, Manager and Director top workflows

- Admin can complete operational search, client and schedule flows from the
  sparse three-destination shell; hidden management destinations normalize to
  an allowed route and do not mount their providers.
- Manager receives funnel, task and status-report capabilities, but no
  `commerce.school_finance.read` destination or request.
- Director receives school/branch finance, reports, access administration and
  the draft/preview/publish/rollback CRM configuration workspace.

Evidence: [student funnel](v6-configurable-student-funnel.md),
[canonical tasks](v6-canonical-tasks.md), [unified dashboard](v6-unified-dashboard.md),
and [unified CRM configuration](v6-unified-crm-configuration.md).

## 100% routed UX state audit

Generated inventory after the S6 changes:

```text
routes=22
production screens=21/21
production-reachable Dart files=260
screen state gaps=0
unowned=0
legacy Back sites=0
```

- production `IconButton` tooltip gaps: `0`;
- duplicated task-create actions per viewport: `0`;
- loading/empty/error/forbidden/retry states: shared and accounted for;
- desktop scroll ownership, mobile full-width expandable sheets, breadcrumbs,
  deep links, dirty-form Back and keyboard focus use the accepted V6 primitives.

Machine-readable evidence:
[route inventory](v6-route-surface-inventory.json),
[navigation inventory](v6-navigation-inventory.json), and
[input/Back inventory](v6-input-back-inventory.json).

## Verification

```text
Flutter role/workflow/navigation suite: 72/72 PASS
Flutter accessibility/state/task suite: 24/24 PASS
Flutter full suite: 601/601 PASS
Flutter analyze: PASS, 0 issues
Server route/evaluator/preflight suite: 78/78 PASS
Server two-session invalidation + actor/leak matrix: 10/10 PASS
Server full Jest/PostgreSQL suite: 152/152 suites, 1177/1177 tests PASS
0098 rollback -> migrate: PASS
Windows client-calendar/context integration: 1/1 PASS
Android 15 API 35 client-calendar/context integration: 1/1 PASS
v6_ux_inventory.ps1 -Check: PASS
server typecheck/build: PASS
```

The 26-point owner script is
[v6-user-workflow-acceptance.md](v6-user-workflow-acceptance.md). No engineering
UX P0 remains open. Signed real-account results, recipient/data reconciliation
and device screenshots belong to V6-701 and are intentionally not fabricated.
