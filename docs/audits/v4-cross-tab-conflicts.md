# T1.2.5 — Shared cache и cross-tab conflicts

- Cache identity включает entity type/id, projection scope и server version.
- Committed invalidation дедуплицируется по event id.
- Clean-вкладки refetch-ятся сразу; dirty-вкладки сохраняют локальный draft и получают conflict state.
- Stale `409` извлекает актуальную server version и показывает Reload / Merge / Cancel.
- Reload и Merge переводят форму на актуальную expected version без silent last-write-wins.

## Проверка

- `flutter test test/features/v4/cross_tab_conflict_test.dart` — 4/4 PASS.
- Регрессия desktop workspace/persistence — 8/8 PASS.
- Targeted Flutter analyze — PASS.
