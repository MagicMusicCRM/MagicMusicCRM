# V6-605 — 26-point owner workflow acceptance pack

**Источник:** `ТЗ СРМ МагМуз-1 (1).docx` and its 21 embedded reference images

**Дата подготовки:** 2026-08-04

**Статус пакета:** READY FOR OWNER EXECUTION

## Engineering UAT candidate — 2026-08-04

- App: `1.2.2+148`
- Git: `c71ecb1512f4c69d1040bc2537ed2bfb8ee3d03d`
- Windows release: `build/windows/x64/runner/Release/magic_music_crm.exe`
- SHA-256: `013A392C01B63A219C49A4DEFA80B5ACF81D7738731B7510E98CBA41BA6B1341`
- Preflight: `flutter analyze` PASS, Flutter `604/604` PASS,
  v6 inventory PASS (`routes=22`, `reachable=260`, `unowned=0`).
- Owner must still record device and backend versions for every executed row;
  this engineering candidate does not replace the required real-account
  signature.

## How to record V6-701

Run each row on the signed build with the named role and scope. Record
`PASS`, `FAIL` or `BLOCKED`, device/app/backend versions, redacted API trace,
observable data result and a screenshot/video link. A row must not be signed
`PASS` from source code alone. `BLOCKED` is the required result when a real
account, provider authority or representative data is unavailable.

| # | Production route / role / scope | Observable result | Engineering evidence | Owner result / artifact / blocker |
|---:|---|---|---|---|
| 1 | CRM desktop shell; every authenticated persona; account | Open 2–10 entity tabs, restart and restore them; logout removes the account cache | ENG PASS — [production mount](v6-production-workspace-mount.md), [restore/logout](v6-workspace-restore-logout.md) | PENDING — Windows capture and signed restart/logout trace |
| 2 | `/leads/new`; Admin+; selected branch | Name, normalized phone and published source are required in UI and backend | ENG PASS — [client forms](v4-client-forms.md), [CRM config](v6-unified-crm-configuration.md) | PENDING — create a representative Lead |
| 3 | `/leads/new`; Admin+; school/branch config | Source is selected only from the effective published dictionary; free text is rejected | ENG PASS — [client config](v4-client-config.md), [CRM config](v6-unified-crm-configuration.md) | PENDING — capture dropdown and invalid payload result |
| 4 | inbound Lead webhook + notification center; configured recipient | Inbound Lead emits the notification once; manual/chat Lead does not | ENG PASS — [inbound Lead](v4-inbound-lead.md) | BLOCKED until real webhook/recipient account; capture delivery trace |
| 5 | `/crm/settings/configuration`; Director; school and branch override | Create/edit/archive sources and fields with usage impact; preview, publish and rollback | ENG PASS — [CRM config](v6-unified-crm-configuration.md) | PENDING — Director capture and before/after values |
| 6 | `/leads/:id` or `/students/:id`; Admin+; client branch | Horizontal canonical card sections stay reachable by mouse, keyboard and touch | ENG PASS — [client workspace](v6-canonical-client-workspace.md), [scrollbars](v6-explicit-desktop-scrollbar-ownership.md) | PENDING — Windows mouse-only capture |
| 7 | client `subscriptions` and Config `subscription_package`; Director; school/branch | Director manages published package catalog; branch override is explicit | ENG PASS — [package catalog](v4-package-catalog.md), [CRM config](v6-unified-crm-configuration.md) | PENDING — Director catalog mutation and rollback |
| 8 | client `subscriptions`; allowed staff; client branch | Replace package atomically with explicit financial decision and one active result | ENG PASS — [subscription replacement](v4-subscription-replace.md) | PENDING — reconcile old/new subscription IDs |
| 9 | client subscription/payment form; Admin+; client branch | Percent or fixed discount changes the immutable commercial snapshot correctly | ENG PASS — [issue/payment](v4-subscription-issue-payment.md), [payments UX](v6-client-payments.md) | PENDING — record base, discount and total |
| 10 | client `payments`; Admin+; client branch | Installments and cash/non-cash payment mode persist and ledger totals reconcile | ENG PASS — [commerce schema](v4-commerce-schema.md), [payments UX](v6-client-payments.md) | PENDING — signed ledger reconciliation |
| 11 | `/students/new`; Admin+; selected branch | Effective required Student fields block incomplete UI and API writes | ENG PASS — [client forms](v4-client-forms.md), [CRM config](v6-unified-crm-configuration.md) | PENDING — valid and invalid Student payloads |
| 12 | client `lessons`; Admin+; client branch | One clearly labelled schedule-create action opens the canonical Lesson flow | ENG PASS — [preferred schedule/Lessons](v6-preferred-schedule-lessons-section.md) | PENDING — capture from Lead and Student cards |
| 13 | global Schedule create; Admin+; selected branch | Typed Lead/Student selector is unambiguous and creates the intended relation | ENG PASS — [ClientRef](v4-client-ref.md), [Lesson form](v4-lesson-form-conflict-ux.md) | PENDING — create one Lead and one Student lesson |
| 14 | Schedule lesson -> client; client `lessons`; allowed actor; branch | Linked client opens; Month/Week/Day calendar marks this client separately from others | ENG PASS — [linked navigation](v6-linked-entity-navigation.md), [client calendar](v6-client-calendar.md) | PENDING — Windows and Android capture |
| 15 | lesson/client drilldown Back; allowed actor; branch | App/system Back restores prior date, mode, branch, filters and scroll context | ENG PASS — [Back policy](v6-unified-back-policy.md); Windows + Android integration PASS | PENDING — owner device capture |
| 16 | Lesson create/edit; Admin+; branch | Missing room/teacher/hours produces structured, understandable violations and no write | ENG PASS — [constraints](v4-schedule-constraint-engine.md), [form UX](v4-lesson-form-conflict-ux.md) | PENDING — seeded invalid attempt |
| 17 | teacher availability/branch assignment; Manager+; school/branch | Effective availability and branch assignment constrain the schedule | ENG PASS — [schedule reference](v4-schedule-reference.md) | PENDING — change rule and confirm matrix result |
| 18 | Lesson create/drag/reschedule; Admin+; branch | Student/teacher/room/branch conflicts are consistent and concurrent writes have one winner | ENG PASS — [constraints](v4-schedule-constraint-engine.md), [concurrency](v4-schedule-concurrency.md) | PENDING — seeded conflict set |
| 19 | Reports export; Manager+; allowed scope | Export downloads a valid OOXML workbook that opens and matches filtered counts | ENG PASS — [OOXML export](v4-ooxml-export.md), [dashboard](v6-unified-dashboard.md) | PENDING — attach exported file and checksum |
| 20 | Students funnel + Config; Manager read / Director config; school/branch | Counts follow the effective configurable funnel; Admin has no config route | ENG PASS — [student funnel](v6-configurable-student-funnel.md), [role acceptance](v6-role-workspace-acceptance.md) | PENDING — reconcile board and API counts |
| 21 | client overview/subscriptions; allowed staff; client branch | Remaining lessons come from the active subscription reservation projection | ENG PASS — [lesson reservations](v4-subscription-lesson-reservations.md), [client read model](v4-client-card-read-model.md) | PENDING — reconcile active subscription count |
| 22 | Tasks / client history-tasks; Manager+; branch or school | All-day/interval, reminder and explicit person/branch/school audiences preview exact recipients | ENG PASS — [canonical tasks](v6-canonical-tasks.md), [audience UX](v6-task-audience-ux.md) | BLOCKED until real recipients/branches; capture preview and delivery |
| 23 | client `history_tasks`; Manager+; client scope | Closing a task creates one close fact, removes mutation affordance and survives refresh | ENG PASS — [shared task API](v4-shared-task-api.md), [tasks UI](v4-shared-tasks-ui.md) | PENDING — close and refresh one client task |
| 24 | Teacher Schedule; Teacher; assigned branches | Day/Week assigned-only calendar and safe drilldowns; no mutation controls or payloads | ENG PASS — [Teacher calendar](v4-teacher-calendar-read-only.md) | PENDING — Teacher account Windows/Android capture |
| 25 | client archive preview/confirm; Director; school/client branch | Linked impact is shown; non-Director is denied; conversion/finance links remain preserved | ENG PASS — [client archive](v4-client-archive.md) | PENDING — preview with linked representative data |
| 26 | completion worker/readiness; system + allowed staff view; branch | Due Lesson completes once; settlement/reservation facts are unique; retry/poison is visible | ENG PASS — [completion worker](v4-lesson-completion-worker.md), [settlement](v4-lesson-settlement.md) | BLOCKED until production-shaped worker window; attach readiness before/after |

## Engineering rehearsal result

The pack maps all 26 requirements to mounted production routes or authoritative
workers, concrete personas and school/branch scopes. Windows and Android 15
context-restoration rehearsals pass. The actor/access matrix, routed UX
inventory and full component gates are recorded in
[v6-role-workspace-acceptance.md](v6-role-workspace-acceptance.md).

Owner signature and real-recipient/ledger/worker observations are intentionally
left pending for V6-701; this document is the execution script, not a simulated
approval.
