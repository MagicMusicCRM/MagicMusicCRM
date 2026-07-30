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
