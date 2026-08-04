# V6-402 — Preferred schedule in Lessons

Date: 2026-08-04  
Status: PASS

## Delivered

- Lead and Student use one preferred-schedule list/editor in the canonical `Занятия` section.
- The old placement in `Обзор` and the generic custom-fields renderer are removed.
- The editor covers effective date range, weekdays, start time, duration, consecutive lessons per day, teacher, room and description.
- The client's branch is selected by default. Existing schedule-series writes require a concrete `branchId`, so an invalid school-wide option is not exposed even when the actor has all-branch scope.
- Reads use the typed `{clientType, clientId}` query; writes use the existing `clientRef` contract and the existing `/crm/schedule-series` endpoints.
- Preferred plan and actual lessons are rendered as separate, labelled surfaces. Legacy free-text preference is preserved as read-only context in the canonical section.
- Create, edit and stop actions follow the existing schedule-series domain. Multi-slot partial success is reloaded and reported explicitly; it is never silently treated as an atomic success.
- Capability projection hides schedule mutations when `schedule.lesson.write` is denied.
- The dirty form participates in the shared system-Back/explicit-cancel confirmation contract.

## Contract evidence

- Service paths/methods are unchanged; the generated wire baseline differs only by source line numbers.
- No new backend/domain path or dependency was added.
- `git diff -- server` is empty.

## Verification

- `flutter analyze`: PASS.
- Related Flutter suite: 87/87 PASS.
- Windows preferred-schedule widget suite: 5/5 PASS.
- Full Flutter suite: 560/560 PASS.
- Route inventory: 21 routes, 262 production-reachable Dart files, 0 unowned.
- Navigation and input/Back inventories: 0 unowned.
- `git diff --check`: PASS.

