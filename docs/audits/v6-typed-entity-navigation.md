# V6-105 — Unified typed entity navigation policy

**Дата:** 2026-08-04  
**Статус:** PASS

## Production policy

- `navigateEntityLink` — единая точка решения для `EntityLink` + `CapabilitySnapshot` + lifecycle через существующий `EntityRouteRegistry`.
- Desktop current-target добавляет запись в историю активной workspace-вкладки; explicit new-target создаёт отдельную вкладку в том же shared session/cache/realtime scope.
- Compact/mobile target использует существующий GoRouter stack, поэтому системный Back возвращает исходный экран.
- `ContextViewState` исходного экрана записывается до перехода и восстанавливает filters/date/scroll/selection после Back.
- Forbidden, missing, archived/deleted refs не меняют navigation state и показывают одинаковое actor-safe сообщение без id/type disclosure.

## Production consumers

- `ProductionWorkspaceHost` публикует один `WorkspaceNavigationScope` для desktop и compact layout; новый direct link обновляет текущую историю без второго workspace.
- `CrmNavigationRequest` из client/staff/notification flows проходит через ту же policy вместо прямого переключения CRM-tab.
- Tasks, reports и reporting drilldowns используют `openEntityLink`/`navigateEntityLink`; прямой `context.push(route.location)` из reporting удалён.

## Проверки

```text
flutter test test/features/v6/typed_entity_navigation_policy_test.dart \
  test/features/v6/production_workspace_mount_test.dart \
  test/features/v4/context_transition_matrix_test.dart \
  test/features/v4/reporting_drilldown_test.dart \
  test/features/v4/shared_tasks_ui_test.dart \
  test/features/messenger/tasks_navigation_test.dart
PASS — 25/25

flutter analyze
PASS — No issues found

git diff -- server
PASS — empty
```

Матрица покрывает все поддержанные `EntityLinkType`, current/new-tab, mobile stack, source-state restore и allow/forbidden/unknown/archived outcomes.
