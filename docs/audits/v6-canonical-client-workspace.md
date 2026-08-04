# V6-401 — Canonical client workspace

Дата приёмки: 2026-08-04.

## Результат

- `Student` и `Lead` открываются через один typed route (`/students/:id` и `/leads/:id`), а desktop использует тот же экран внутри активной account-scoped workspace-вкладки.
- Production launcher больше не создаёт фиксированный `600 px` dialog. Compact получает полноэкранный route; desktop — всю рабочую область.
- Канонические section keys: `overview`, `lessons`, `payments`, `subscriptions`, `history_tasks`, `contacts`, `documents`, `custom_fields`.
- Section сохраняется в URL query на compact и в `ContextViewState` desktop-вкладки. Переход между sections не повторяет загрузку клиента.
- Capability deny отрабатывает до монтирования client fetcher; Teacher получает существующую ограниченную projection-карточку, staff — полную actor-safe карточку.
- Существующие формы, providers и API paths переиспользованы. Wire/service baseline и `server/` не изменились.

## Доказательства

- Role × viewport: Admin/Manager/Director на `360/840/1200`, deny case и production desktop host — PASS.
- Stable section deep link round-trip и direct-link update без refetch — PASS.
- Routed и прежний content host дают идентичный client API trace — PASS.
- Связанный regression pack: `49/49`.
- Windows targeted: `13/13`.
- Full Flutter: `552/552`; `flutter analyze`: clean.
- UX inventory: routes `21`, production-reachable files `261`, state gaps `0`, unowned `0`.
- `git diff -- server`: empty; wire/service baseline: unchanged.

