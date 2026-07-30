# T1.2.2 — Mobile context stack и restoration

Дата: 2026-07-30

## Результат

- Создан restorable `ContextRouteState`: EntityLink + filters/date/scroll/column.
- Четырёхуровневый drilldown использует обычный mobile stack без tab strip.
- Перед push состояние source screen фиксируется; последовательный Back
  восстанавливает каждый уровень без потери контекста.
- Unauthenticated deep link хранится как pending EntityLink; после входа
  строится стек `home → target`, поэтому Back возвращает в корректный home.
- Сериализация содержит только route/view references, без DTO, токенов и
  незавершённых значений форм.

## Проверка

- Flutter unit/widget: 4/4 tests.
- Targeted Flutter analyze: clean.
- Full Flutter regression/analyze: 461/461 tests, PASS.
- Full backend regression/typecheck/build: 144/144 suites, 1140/1140 tests, PASS.
- Inventory/access coverage: 287 routes, 658 DTO fields, 0 unowned;
  275/275 private routes mapped.
