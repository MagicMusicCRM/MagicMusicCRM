# V4 Lead, Student and configuration forms — T3.3.1

Дата: 2026-07-30
Статус: PASS

## Реализация

- Ручные `POST /crm/leads` и `POST /crm/students` подключены к strict
  validators T3.1.2; source/branch/status и обязательные custom fields
  проверяются до начала записи.
- Нормализованные custom values сохраняются в той же транзакции, что Lead или
  Student. Неполная карточка не появляется.
- Flutter формы используют только активные справочники, сохраняют введённые
  значения при 422 и показывают ошибку у конкретного поля.
- `SOURCE_INACTIVE` обновляет список источников и требует новый выбор без
  очистки ФИО/телефона/custom fields.
- Source/custom-field editor использует versioned CRUD/archive API и
  отображается только при `system.settings.manage`; 403 обработан внутри
  диалога.
- Mobile 320 dp использует scrollable bounded layout без overflow; предусмотрены
  loading, empty, error и retry состояния.

## Верификация

- `client_forms_test.dart`: 4/4 widget tests.
- Client config/manual write boundary: 3/3 suites, 9/9 tests.
- Backend typecheck: clean.
- Flutter analyze: clean.
