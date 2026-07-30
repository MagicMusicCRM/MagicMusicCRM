# INT-S4 — CRM & Shared Work

Дата: 2026-07-30

## Результат

Sprint gate `S4` завершён со статусом `PASS` за 36.275 с. Проверены все задачи T3.1.2–T3.3.2 и T6.1.1–T6.4.1, их evidence и единый actor/device boundary.

## Подтверждённые инварианты

- Ручное создание Lead не создаёт inbound-уведомление.
- Повтор одного inbound ingestion создаёт ровно один Lead и одно уведомление.
- Архивация доступна только Director и system_admin, всегда через preview/version/reason/confirm.
- Два одновременных закрытия SharedTask возвращают один стабильный результат и один набор фактов.
- Teacher Client Card не запрашивает и не показывает контакты, представителей, финансы и абонементы.
- Mobile collapsed task filter имеет высоту 56 px; расширенные фильтры прокручиваются, desktop-фильтры остаются inline.

## Проверки

- Backend CRM lifecycle/privacy: 6/6 suites, 21/21 tests.
- Backend SharedTask audience/concurrency/reminders: 3/3 suites, 5/5 tests.
- Actor Matrix и payload leak: 2/2 suites, 9/9 tests.
- Flutter CRM/task mobile+desktop: 12/12 tests.
- Backend TypeScript: clean.

Машиночитаемый результат: `docs/audits/v4-s4-gate-result.json`.
