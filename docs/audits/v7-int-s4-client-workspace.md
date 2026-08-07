# v7 INT-S4 — Client Workspace

**Дата:** 2026-08-07

**Решение:** PASS

**Проверенная ревизия:** `a56ad8f`

## Принятый контур

Одна production `ClientCard` подтверждена как канонический Lead/Student
workspace. Проверены профильные секции и владельцы действий, client commerce,
постоянные расписания, заметка, staff-only operational history, Director
commerce configuration и запрет скрытых запросов для младших ролей.

## Ролевой и маршрутный smoke

- Реальные `magic1..5@gmail.com` на `https://api.magicmusiccrm.ru/api`:
  Windows `2/2`, Android 15/API 35 `2/2`. Проверены роли Client, Teacher,
  Admin, Manager, Director, защищённое восстановление сессии, restart,
  logout и переключение `magic1 → magic5 → magic1`.
- Детерминированная production-card story на Windows и Android: `3/3` на
  каждой платформе. Она монтирует настоящий UI с записывающим API seam и не
  изменяет production-данные.
- Lead и Student имеют по одному `subscription-add` и `assign-homework` в
  профильных секциях; общего меню «Действия» нет. Payments/installments по
  умолчанию свёрнуты.
- Desktop использует один canvas и section jumps; compact использует тот же
  набор секций. Canonical route/back и parity routed/legacy API trace входят
  в целевой Flutter gate.

## Проверенные истории

| История | Результат |
|---|---|
| Staff note | optimistic `expectedVersion=4`, точный PUT body, автор/время видимы |
| Operational history | действие, точная причина и актор видимы staff |
| Payment status | `posted_pending → unpaid`, обязательная причина сохранена |
| Payment reversal | preview → confirmed technical void, причина сохранена |
| Technical history | удалённая из обычного учёта запись остаётся видимой staff |
| Teacher boundary | finance/note/history controls отсутствуют; forbidden GET = `0` |
| Recurring plans | active/ended, tray, create/edit/end и Back подтверждены INT-S3 |
| Configuration | два независимых Director-only каталога; прочие роли без provider/control |

Санитизированный network trace печатается самим device-тестом. Staff trace
содержит только ожидаемые card/commerce/history reads и versioned mutations;
Teacher trace не содержит `/commerce`, `/internal-note` или
`/operational-history`.

## Автоматические ворота

- Flutter targeted Client Card/config/schedule: `41/41`.
- Backend Client Card/commerce/plan/config/RBAC PostgreSQL contracts:
  `6/6` suites, `102/102` tests.
- Windows device story: `3/3`.
- Android 15/API 35 device story: `3/3`.
- Android application logcat: Flutter/FATAL/unhandled/overflow errors `0`.
- v6 UX inventory: routes `22`, reachable Dart `260/261`, navigation `265`,
  wire `274/274`, all inventories `unowned=0`.
- v7 inventory: finance callsites `251`, reporting-safe reads `51`, protected
  lesson mutations `7`, unknown callers `0`, `unowned=0`.
- `git diff -- server`: empty.

## Найденный и устранённый дефект

Android device gate обнаружил overflow карточки при закрытии финансового
bottom sheet с открытой IME. Причиной была фиксированная высота dialog-card,
конфликтовавшая с анимируемым системным inset. `ClientCard` теперь задаёт
только максимальную высоту `85%` и всегда принимает текущие ограничения
диалога. Полный Windows/Android повтор после исправления зелёный.

## Итог

INT-S4 принят. Дубликатов команд и запрещённых запросов не найдено; причины и
техническая история доступны Admin/Manager/Director и не протекают
Teacher/Client. Следующий обязательный gate — `T6.1.1` full
regression/security/reconciliation.
