# MagicMusicCRM v6 — S0 Baseline Evidence

**Tasks:** V6-001…V6-005  
**Date:** 2026-08-04  
**Source revision before S0 implementation:** `1b0372f`  
**Result:** PASS

## Toolchain

| Tool | Version |
|---|---|
| Flutter | 3.41.4 |
| Dart | 3.11.1 |
| Node.js | 24.18.1 |
| npm | 11.16.0 |

## Reproducible gates

| Gate | Result |
|---|---|
| `flutter analyze` | PASS — no issues |
| `flutter test` | PASS — 486/486 |
| `npm --prefix server run typecheck` | PASS |
| `npm --prefix server run build` | PASS |
| `npm --prefix server test` | PASS — 150/150 suites, 1160/1160 tests |
| `npm --prefix server run test:actor-matrix:v4` | PASS — 2/2 suites, 9/9 tests |
| Targeted Flutter service/workflow contracts | PASS — 68/68 |
| `pwsh -File scripts/v4_inventory.ps1 -Check` | PASS — routes=287, DTO fields=660, schema tables=5, unowned=0 |
| `pwsh -File scripts/v6_ux_inventory.ps1 -Check` | PASS — unowned=0, checked artifacts current |

Targeted Flutter command:

```powershell
flutter test `
  test/core/services/magic_crm_service_test.dart `
  test/features/v4/lesson_form_test.dart `
  test/features/v4/shared_tasks_ui_test.dart `
  test/features/v4/reporting_drilldown_test.dart `
  test/features/v4/client_card_roles_test.dart `
  test/features/v4/subscription_issue_form_test.dart `
  test/features/manager/manage_statuses_save_order_test.dart
```

This set records request mapping and user-flow contracts for Schedule, Client card, Payment/subscription, Shared Tasks, Reporting drilldowns and configured status ordering. The PostgreSQL actor/payload suite supplies the seeded six-principal access and leak baseline. It does not replace S7 real-account UAT.

## Current-state facts

| Slice | Evidence |
|---|---:|
| Dart files | 259 |
| Files statically reachable from `main.dart` | 248 |
| GoRouter production routes | 21 |
| Production-reachable Screen/Page classes | 21 |
| Reachable modal/sheet/drawer callsites | 98 |
| Production workspace usages outside definitions | 0 |
| EntityLink types | 19 |
| Direct navigation sites requiring classification | 256 |
| Production scroll sites | 141 |
| Explicit scrollbar callsites | 3 |
| Static Flutter service/API callsites | 256/256 production-reachable |

Counts are generated rather than hand-maintained. The authoritative values are the four `v6-*-inventory.json` artifacts; this table is a baseline snapshot and must be updated if the generator changes.

## Runtime boundaries (`runtime-inspector`)

- Flutter root: `lib/main.dart`; HTTPS/JSON and Socket.IO client.
- NestJS root: `server/src/main.ts`; HTTP/JSON and Socket.IO server backed by PostgreSQL.
- Child processes: Windows updater PowerShell and security-gate scan commands; both remain platform lifecycle surfaces, not CRM navigation channels.
- API contract strength: typed Dart service methods + NestJS DTO/policy registry over JSON. Runtime version mismatch remains guarded by release/API compatibility tests rather than an IPC handshake.

## Baseline limitations carried to later gates

- Workspace implementation exists but is not mounted in production (`workspaceProduction=0`).
- Device input behavior cannot be proven by static inventory: Windows mouse-only is required at INT-S3/S7.
- Android predictive Back and full-width draggable sheet require device evidence at INT-S2/S7.
- Real-account recipients, branches and owner workflows remain S7 evidence; they are not claimed by seeded tests.
