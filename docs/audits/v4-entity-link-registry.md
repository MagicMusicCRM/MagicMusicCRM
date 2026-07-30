# T1.2.1 — EntityLink registry

Дата: 2026-07-30

## Результат

- Создан versioned `EntityLink` v1 с typed entity, id и optional focus/filter.
- Зарегистрированы Client/Lesson/Task/Subscription/Payment/User/Homework/Chat/Report targets.
- Server variants `lead`, `student`, `client_status_list`, `lesson_list` и
  `school_finance_month` нормализуются без потери исходного типа.
- Navigation policy использует текущий capability snapshot и fail-closed
  решение; Teacher Client route получает только limited projection.
- Forbidden/deleted/archived/unknown ссылки завершаются безопасным состоянием
  без бесконечной загрузки.

## Проверка

- Flutter unit/widget: 4/4 tests.
- Targeted Flutter analyze: clean.
