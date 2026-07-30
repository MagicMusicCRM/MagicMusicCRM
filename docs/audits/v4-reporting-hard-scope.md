# T7.1.2 — Lesson и Finance reporting scope

Дата: 2026-07-30

## Результат

- Lesson Success вычисляется только из `Lesson.lifecycle_state = successfully_completed`.
- Manager metric ограничен текущими назначениями филиалов на уровне SQL.
- Client Finance и School Finance используют раздельные существующие политики.
- School Finance доступен только Director и system_admin.
- Revenue суммируется из append-only `payments.amount_minor`; expected installments не участвуют.
- Финансовые EntityLink присутствуют только в разрешённой root-business проекции.

## Проверка

- PostgreSQL integration: 1/1 suite, 2/2 tests.
- Admin/Manager School Finance: `403`.
- Director/system_admin ActualPayment projection: PASS.
- TypeScript typecheck: clean.
