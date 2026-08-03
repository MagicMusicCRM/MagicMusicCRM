# INT-S1 — Navigation/workspace kernel acceptance

**Дата:** 2026-08-04  
**Решение:** PASS

## Принятый контур

- Один `EntityRouteRegistry` задаёт canonical location, capability policy, typed breadcrumbs и direct-link reconstruction.
- Production desktop workspace смонтирован для staff roles; compact layout остаётся одним mobile route stack.
- Account-scoped tabs, per-tab Back/Forward, view state, restart restore, role downgrade и logout reset покрыты тестами.
- Desktop context bar и 1–8 breadcrumb nodes работают на `840/1000/1200 px`, включая keyboard focus, ellipsis и action overflow.
- Один `navigateEntityLink` управляет current/new desktop target и mobile GoRouter target; запрещённый target не меняет workspace/router и не инициирует entity prefetch.

## Gates

```text
flutter analyze
PASS — No issues found

flutter test
PASS — 503/503

flutter build windows --debug
PASS — build/windows/x64/runner/Debug/magic_music_crm.exe

scripts/v6_ux_inventory.ps1
scripts/v6_ux_inventory.ps1 -Check
PASS — routes=21, reachable=255, workspaceProduction=2, unowned=0

EntityRouteRegistry definition count
PASS — 1

direct context.push/go(route.location) entity bypass count
PASS — 0

git diff --check
PASS

git diff -- server
PASS — empty
```

## Negative navigation evidence

`typed_entity_navigation_policy_test.dart` проверяет все поддержанные типы, forbidden/unknown/archived outcomes и отсутствие изменения router/workspace. Policy принимает уже actor-scoped `CapabilitySnapshot` и до успешного resolution не вызывает provider/service сущности; следовательно forbidden deep link не создаёт запрещённого prefetch и не раскрывает существование записи.

## Итог

`V6-101..105` и `INT-S1` приняты. CH-01/CH-08 закрыты на уровне navigation/workspace kernel; дальнейшая миграция экранов обязана использовать этот контур без второго router/tab registry.
