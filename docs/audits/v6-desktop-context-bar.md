# V6-104 — Desktop context bar и breadcrumbs

**Дата:** 2026-08-04  
**Статус:** PASS

## Production mounting

- `ProductionWorkspaceHost` добавляет context bar над содержимым активной desktop-вкладки при ширине `>=840`; compact/mobile shell не получает второй navigation stack.
- Заголовок, ancestor trail, route и capability metadata берутся из существующего `EntityRouteRegistry`.
- Ancestor открывается в текущей workspace-вкладке; Back/Forward работают с независимой историей этой вкладки и сохраняют `ContextViewState`.
- Forward history сериализуется в существующий account-scoped secure workspace snapshot и повторно проходит capability validation при restore.
- Текущий breadcrumb — read-only; Back/Forward, path menu и page-actions menu имеют keyboard focus, tooltip и semantics.

## Responsive contract

- Проверены 1–8 узлов и длинные русские заголовки на `840/1000/1200 px` без overflow.
- Скрытая часть пути доступна через ellipsis menu; current node всегда остаётся видимым с ellipsis текста.
- Page actions используют один overflow menu, без дублирования action state.

## Проверки

```text
flutter test test/features/v6/desktop_context_bar_test.dart \
  test/features/v4/desktop_workspace_controller_test.dart \
  test/features/v4/workspace_persistence_logout_test.dart \
  test/features/v6/canonical_app_location_test.dart \
  test/features/v6/production_workspace_mount_test.dart
PASS — 21/21

flutter analyze
PASS — No issues found

git diff -- server
PASS — empty
```

Покрыты keyboard ancestor jump, current-node non-clickability, Back/Forward, history persistence, direct-link reconstruction, responsive layout и action/path overflow.
