# T6.3.1 — Shared Tasks desktop/mobile UX

Дата: 2026-07-29

## Результат

- Новый экран «Общие задачи» подключён к действующему разделу задач без удаления legacy calendar/history.
- Flutter использует v4 `/crm/shared-tasks` create/update/list/close и сохраняет mutation identity при retry.
- Карточка содержит явное действие «Закрыть задачу» и состояния pending/error/retry.
- Reminder отображается как badge/panel и не блокирует текущий route.
- Editor поддерживает all-day/interval и audience: сотрудники, филиал, все филиалы.
- Desktop использует inline filters; mobile collapsed filter имеет фиксированную высоту 56 px, расширенные фильтры находятся в scrollable bottom sheet.
- Realtime body-free task hint запускает actor-scoped refetch.
- API projection возвращает audiences и pending reminders, необходимые для безопасного edit.

## Проверки

- `flutter test test/features/v4/shared_tasks_ui_test.dart`: 4/4 PASS.
- `flutter analyze --no-pub`: No issues found.
- SharedTask backend targeted regression: 2 suites, 3/3 tests.
- Backend typecheck: PASS.
