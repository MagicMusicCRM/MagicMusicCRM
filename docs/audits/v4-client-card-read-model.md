# V4 role-aware Client Card read model — T3.2.4

Дата: 2026-07-30  
Статус: PASS

## Контракт

- `GET /crm/clients/:type/:id/card` принимает явный `ClientRef`
  (`lead|student`) и сохраняет compatibility route
  `GET /crm/students/:id/card`.
- Header, indicators и секции собираются одним batched composition query
  после actor-scoped resolver и effective capability snapshot.
- Query count фиксирован: 3 запроса независимо от количества Lesson, Task,
  Homework, Comment, Group и Subscription строк.
- Indicators (`nextLesson`, counts by state/status, active subscription
  remainder) вычисляются из source systems; локальный future menu не является
  источником данных.

## Role projections

- Staff full: overview, groups, lessons, tasks, homework, comments и finance
  только при `commerce.client_finance.read`.
- Teacher: только assigned lessons/homework и явно shared comments; contacts,
  representatives, finance, payments, subscriptions и balance keys = 0.
- Client: own lessons/homework, progress comments и own finance при capability.
- Чужой UUID для Teacher возвращает safe 404 до composition query.

## Верификация

- Client Card PostgreSQL/controller suite: 3/3 suites, 10/10 tests.
- Actor Matrix + payload leak + Client Card: 3/3 suites, 13/13 tests.
- Actor Matrix: 268 private routes × 6 actors = 1608/1608 decisions.
- Inventory: 280 routes, 641 DTO fields, 0 unowned.
- Backend typecheck: clean.
