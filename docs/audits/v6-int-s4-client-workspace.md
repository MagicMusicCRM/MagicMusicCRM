# INT-S4 — Client Workspace Acceptance

Date: 2026-08-04
Status: ACCEPTED

## Acceptance

| Gate | Evidence | Result |
|---|---|---|
| Canonical full card | Student/Lead production routes, desktop workspace host and compact full-screen route use one client content implementation | PASS |
| Lessons | Preferred schedule and bounded Month/Week/Day calendar live only in `Занятия`; hidden section performs no schedule request | PASS |
| Payments | One canonical immutable ActualPayment flow; branch, positive minor units, actor and idempotent retry validated | PASS |
| Configurable Student entry | Main `Ученики` and legacy Management entry use one form, one effective school/branch funnel and one API path | PASS |
| Linked navigation | Typed lesson/client/task/payment/subscription references, desktop current/new-tab, compact stack, unavailable state and exact Back restoration | PASS |
| Role/scope | Admin/Manager/Director workspace matrix, Teacher redaction, capability deny before client fetch and actor payload-leak checks | PASS |
| CH-06 | Calendar requests only the visible Month/Week/Day interval, one branch and at most 500 actor-visible rows; hidden tab prefetch is zero | CLOSED |
| CH-11 | Client relation uses marker, label and tint independently from lifecycle, trial and conflict; non-color legend and semantic labels remain present | CLOSED |
| Wire/reconciliation | Inventory regenerated after S4; 260/260 existing reachable calls, process roots 2, unowned 0, backend contracts unchanged | PASS |

## Device evidence

```text
flutter test integration_test/v6_client_calendar_device_test.dart -d windows
PASS — 1/1, native Windows debug build

flutter test integration_test/v6_client_calendar_device_test.dart -d emulator-5554
PASS — 1/1, Android 15 / API 35
```

Both runs execute `client card → client lesson → schedule → Back → restored calendar` and finish with zero Flutter exceptions.

## Automated gate

```text
flutter analyze
PASS — no issues

flutter test test/features/v6
PASS — 65/65

flutter test
PASS — 586/586

backend typecheck + build
PASS

commerce PostgreSQL/contract suite
PASS — 8/8 suites, 38/38 tests

client-ref/archive + funnel + actor/payload scope
PASS — 5/5 suites, 21/21 tests

pwsh scripts/v6_ux_inventory.ps1 -Check
PASS — routes=21, reachable=264, workspaceProduction=2, unowned=0

git diff --check
PASS

git diff -- server
PASS — empty
```

## Reconciliation note

The generated wire inventory moved from 256 to 260 callsites because the four approved Student funnel read/publish/rollback callsites delivered in V6-405 are now production-reachable. Semantic comparison found no replacement or parallel transport path; all 260 callsites are owned and use the existing shared API client.

This sprint gate accepts the S4 client workspace only. Real-account five-role UAT, production security and final release approval remain explicitly owned by INT-S7.
