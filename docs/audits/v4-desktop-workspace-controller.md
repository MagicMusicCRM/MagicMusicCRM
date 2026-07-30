# T1.2.3 — Desktop WorkspaceController

- Добавлены `WorkspaceState`, `WorkspaceTabState` и active-tab selection.
- Route stack и form registry изолированы внутри вкладки.
- Session/cache/realtime передаются единым `WorkspaceSharedScope`.
- Обычное открытие фокусирует существующую entity; explicit-new создаёт второй контекст.
- Верхняя desktop tab strip поддерживает переключение 1–10 вкладок.

## Проверка

- `flutter test test/features/v4/desktop_workspace_controller_test.dart` — 4/4 PASS.
- Targeted Flutter analyze — PASS.
