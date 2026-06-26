# Performance Audit Report

Дата: 2026-06-25
Среда: staging `https://api.phantom-net.ru/api`, сервер `161.104.50.105`
Статус: первичный baseline + root-cause audit. Оптимизационные правки, миграции и frontend/backend refactor не применялись.

## Executive Summary

Текущий live baseline не подтверждает, что одиночные REST endpoint'ы стабильно занимают 10-20 секунд. На staging большинство API-вызовов отвечают быстрее 500 мс, сохранения задач/уроков/сообщений укладываются в 55-65 мс, а realtime delivery через Socket.IO занял примерно 52-60 мс вместе с POST-запросом.

Но ощущение "вкладки грузятся 10-20 секунд" имеет правдоподобные root cause:

1. Экран открывает несколько endpoint'ов каскадом, часто с повторной загрузкой справочников (`branches`, `teachers`, `students`, `admin/profiles`) вместо одного lightweight initial payload.
2. Некоторые endpoint'ы возвращают слишком тяжёлые payload'ы: `schedule matrix month` 707 KB, `students search` 498 KB, `lead board` 169 KB.
3. Есть реальные SQL hot paths:
   - `/admin/profiles?limit=100` - 471 мс live, SQL 440 мс.
   - `/crm/rooms/availability` - 189 мс live, SQL 178 мс.
   - `/crm/students/search?limit=500` - 224 мс live, payload 498 KB.
   - `/crm/me` для клиента - 162 мс live, где `listLessons` даёт 123 мс.
4. Flutter state/realtime слой может создавать refetch bursts: глобальный fallback poll каждые 30 секунд для 10 entity types и chat fallback poll каждые 12 секунд при realtime silence.
5. В `pg_stat_statements` есть исторические следы очень тяжёлых CRM-запросов; часть исправлена индексами, но часть всё ещё требует rewrite и p95-harness.

Главный вывод: первым надо чинить не "сервер слабый", а waterfall загрузки экранов, тяжёлые DTO/payload, два SQL hot path и realtime invalidation/refetch. На текущем VPS нет признаков CPU/RAM/disk saturation.

## Current Metrics

Методика: публичный HTTPS API, JWT по staging smoke-аккаунтам, замер wall-clock latency, payload bytes, delta по `pg_stat_statements` вокруг запроса. Для composite screen rows указано суммарное число REST/SQL по measured screen bundle.

| Экран/действие | Сейчас, сек | Цель, сек | API-запросы | SQL-запросы | Размер ответа | Главная проблема |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Health | 0.004 | 0.1 | 1 | 0 | 86 B | Нет |
| Админ dashboard `/crm/dashboard/manager` | 0.063 | 0.5-1.0 | 1 | 1 | 555 B | Сейчас OK; исторически были медленные варианты |
| Overview `/crm/overview` | 0.011 | 0.5 | 1 | 1 | 144 B | Нет |
| Отчёты/финансы `/crm/reports/finance` | 0.023 | 1.0 | 1 | 3 | 3.9 KB | 3 последовательных query, но сейчас OK |
| Список учеников `/crm/students` | 0.095 | 1.0 | 1 | 1 | 81.5 KB | Payload и агрегации, нет cursor/page model для больших филиалов |
| Доска учеников `/crm/students/search?limit=500` | 0.224 | 1.5 | 1 | 1 | 498.4 KB | Загружает крупный board payload, frontend группирует/фильтрует |
| Список лидов `/crm/leads` | 0.013 | 1.0 | 1 | 1 | 95.8 KB | Payload для list-view великоват |
| Lead board `/crm/leads/board` | 0.045 | 1.0 | 1 | 3 | 169.0 KB | Пагинация по статусам есть, payload всё ещё крупный |
| Расписание месяц `/crm/schedule/matrix` | 0.089 | 1.5-2.0 | 1 | 1 | 707.7 KB | Month view отдаёт слишком детальные lesson objects |
| Расписание день `/crm/schedule/matrix` | 0.022 | 0.5-1.0 | 1 | 1 | 60.6 KB | OK |
| Availability аудиторий `/crm/rooms/availability` | 0.189 | 0.5 | 1 | 1 | 15.7 KB | SQL overlap checks сканируют `lessons` многократно |
| Список уроков день `/crm/lessons` | 0.018 | 0.5 | 1 | 1 | 27.5 KB | OK |
| Список преподавателей `/crm/teachers` | 0.106 | 0.5-1.0 | 1 | 1 | 24.2 KB | Lateral/aggregate query, пока приемлемо |
| Задачи `/crm/tasks` | 0.036 | 0.5-1.0 | 1 | 1 | 74.4 KB | Payload умеренный, frontend refetch после mutation |
| Группы `/crm/groups` | 0.012 | 0.5 | 1 | 1 | 27.0 KB | OK |
| Абонементы `/crm/subscriptions` | 0.007 | 0.5 | 1 | 1 | 292 B | OK |
| Пакеты абонементов `/crm/subscription-packages` | 0.005 | 0.5 | 1 | 1 | 534 B | OK, хороший cache candidate |
| Оплаты `/crm/payments` | 0.011 | 0.5-1.0 | 1 | 2 | 38.3 KB | OK; проверить page size на реальном диапазоне |
| Профили staff/admin `/admin/profiles?limit=100` | 0.471 | 0.5 | 1 | 1 | 16.4 KB | Коррелированные counts + regexp phone normalization per row |
| Карточка клиента/ученика bundle | 0.092 | 1.0-1.5 | 7 | 14 | ~0.9 KB main + secondary | 4 повторных student select, вторичные блоки можно lazy load |
| Карточка лида bundle | 0.024 | 1.0 | 4 | 7 | ~0.7 KB main + secondary | Сейчас OK |
| Профиль клиента `/profile/me` | 0.005 | 0.5 | 1 | 1 | 442 B | OK |
| Кабинет клиента `/crm/me` | 0.162 | 0.5-1.0 | 1 | 6 | 3.7 KB | Generic `listLessons` в summary даёт 123 мс SQL |
| Кабинет преподавателя: ученики | 0.010 | 1.0 | 1 | 1 | 655 B | Smoke teacher имеет мало данных; нужен real-teacher p95 |
| Кабинет преподавателя: уроки день | 0.014 | 0.5-1.0 | 1 | 1 | 12 B | Smoke teacher пустой; нужен real-teacher p95 |
| Системный чат: chat list | 0.019 | 0.5 | 1 | 1 | 1.4 KB | API OK; риск на Flutter polling/rebuild |
| Чат клиента: chat list | 0.022 | 0.5 | 1 | 1 | 728 B | API OK |
| Чат клиента: messages `limit=50` | 0.009 | 0.5 | 1 | 2 | 9.9 KB | Pagination есть; проверить long chat cursor |
| Отправка сообщения | 0.013 | 0.5-1.0 | 1 | 11 | 599 B | API OK; SQL count высокий, но latency низкая |
| Realtime client->admin message | 0.052 | 0.3-1.0 | 1 + ws | n/a | event small | OK; event пришёл до завершения REST promise |
| Realtime admin->client message | 0.060 | 0.3-1.0 | 1 + ws | n/a | event small | OK |
| Создание задачи | 0.055 | 0.3-0.8 | 1 | ~4 | 482 B | OK; cleanup выполнен |
| Создание оплаты | 0.174 | 0.5-1.0 | 1 | ~4 | 406 B | OK; есть idempotency guard |
| Создание урока | 0.065 | 0.5-1.0 | 1 | ~9 | 542 B | OK; SQL count из-за audit/affected users |
| Редактирование урока | 0.058 | 0.5-1.0 | 1 | ~5 | 550 B | OK |

## Main Bottlenecks

### PostgreSQL

`pg_stat_statements` включён и preloaded. DB size около 221 MB, cache hit около 99.96%, deadlocks 0, активных соединений мало. Это не похоже на ресурсное голодание Postgres.

Доказанные query-shape проблемы:

1. `/admin/profiles?limit=100`: live 471 мс, SQL 440 мс. `EXPLAIN ANALYZE` по основному фрагменту показал per-profile subplans, seq scan `students` 39 раз и regexp-normalization phone в join/filter. Даже урезанный EXPLAIN выполнялся 135 мс; полный endpoint дороже, потому что считает ещё candidates по leads/teachers/staff.
2. `/crm/rooms/availability`: `EXPLAIN ANALYZE` 179 мс, 169119 shared buffer hits. `SubPlan 1` и `SubPlan 3` для overlap checks многократно сканируют `lessons`: `Rows Removed by Filter` 29616 и 42749 на room loop.
3. Исторические stats: `groups` и `lessons` имеют огромные `seq_scan/seq_tup_read` counters. Часть уже закрыта миграциями `0039_crm_hot_path_indexes` и `0038_perf_indexes`, но надо смотреть deltas после reset/наблюдения, а не только накопительные счётчики.

### Backend

1. Backend отдаёт heavy DTO там, где screen first paint требует summary:
   - `schedule matrix month` 707 KB.
   - `students search limit=500` 498 KB.
   - `lead board` 169 KB.
2. `getMySummary` вызывает generic `listLessons/listTasks/listPayments`. Для клиента нужен специализированный summary-query, а не полный operational list DTO.
3. `listProfiles` смешивает list-view и expensive linking/candidate diagnostics. Эти counts должны быть optional expansion или отдельным endpoint.
4. Для карточки ученика secondary blocks измерены как bundle с 14 SQL. Основная карточка должна открываться отдельно, а lessons/payments/tasks/comments/expected payments догружаться секциями.

### Flutter Frontend

По static audit:

1. `students_board_providers.dart` загружает до 500 учеников branch-wide и группирует на клиенте. В коде уже есть TODO на server pagination/board endpoint.
2. `tasks_widget.dart` грузит `_loadFilterData` (`branches + admin/profiles`) и `_loadTasks`; create dialog снова грузит profiles/students/teachers.
3. `schedule_widget.dart` может грузить matrix + room availability на экранном пути. Availability должен быть lazy только для create/edit flow или выбранного дня/слота.
4. `teacher_students_widget.dart` и `teacher_schedule_widget.dart` сначала ищут teacher через `listTeachers(limit:1)`, затем грузят данные. Это лишний round trip; backend должен отдавать teacher/self context.
5. Messenger screen большой stateful widget с fallback polling и множеством `setState`; высок риск полного rebuild дерева при частых событиях.

### Realtime

Backend realtime path быстрый в smoke: message delivery 52-60 мс. Риск не в Socket.IO transport, а в клиентской инвалидации:

1. `crm_realtime_provider.dart` имеет fallback timer каждые 30 секунд и генерирует poll-events для 10 entities.
2. Messenger fallback poll каждые 12 секунд после silence может конкурировать с live events.
3. Если screen listeners делают full provider invalidation/refetch на каждое событие, UI будет лагать даже при быстром backend.

### Server/Infrastructure

Snapshot:

- load avg: `0.02, 0.04, 0.06`
- CPU idle около 95%
- RAM 7.9 GB total, около 6.8 GB available
- disk `/`: 119 GB total, 9.9 GB used
- no swap
- containers healthy

Вывод: текущие задержки не доказаны CPU/RAM/disk bottleneck. Апгрейд VPS сейчас не является первым исправлением.

## Critical Performance Issues

1. `/admin/profiles` нужно переписать: list endpoint не должен считать все linked/candidate counts для каждой строки.
2. `/crm/rooms/availability` overlap logic нужно переписать: сначала ограничить candidate lessons по range/room, затем считать conflicts внутри CTE; добавить partial covering indexes.
3. `schedule matrix month` должен иметь лёгкий month summary DTO. Полный lesson DTO нужен для day/detail, не для первого paint месяца.
4. `students/search limit=500` должен стать paginated/cursor или board-specific endpoint с минимальным DTO.
5. Flutter должен перестать блокировать tab open на справочниках и secondary blocks.
6. Realtime invalidation должен быть targeted: update local item или invalidate one section, не refetch всей вкладки.

## Quick Wins

1. Не открывать `room availability` при входе в расписание; грузить только при create/edit lesson или при явном выборе слота.
2. Для month schedule использовать `/crm/schedule/month-summary` или новый lightweight endpoint, full matrix только для day/week detail.
3. В `tasks_widget` кэшировать справочники через Riverpod provider с TTL 5 минут: branches, rooms, lead statuses, teachers, staff summary.
4. В create dialogs переиспользовать уже загруженные reference providers, не дергать `admin/profiles` повторно.
5. Для `/admin/profiles` добавить query flag `includeLinkCounts=false` по умолчанию; counts грузить по раскрытию профиля.
6. Ограничить fallback realtime poll: запускать только когда socket disconnected или screen active, и не эмитить все 10 entity types глобально.
7. В UI после create/update применять локальное patch/update state вместо full reload всего списка, где это безопасно.

## Deep Fixes

1. `ProfileService.listProfiles`: разнести lightweight profile list и expensive link diagnostics.
2. `CrmService.listRoomAvailability`: rewrite overlap query под bounded lessons CTE + room aggregate.
3. `CrmService.getMySummary`: отдельный client summary query без generic `listLessons`.
4. `Students board`: server-side pagination/search/filter/sort + minimal board card DTO.
5. `Student card`: route-level lazy sections: main profile first, затем lessons/payments/tasks/comments/expected payments independently.
6. `Realtime`: event reducer/deduplication by `entity/action/id/version`, targeted provider updates, throttle burst events.

## Database Optimization Plan

Индексы ниже не применять вслепую. Перед миграцией нужен `EXPLAIN (ANALYZE, BUFFERS)` на production-like snapshot и `CREATE INDEX CONCURRENTLY` в отдельной миграции.

### Candidate Indexes

| Таблица | Поля | Причина | Ускоряет | Риск | SQL migration |
| --- | --- | --- | --- | --- | --- |
| `app.lessons` | `(room_id, scheduled_at) include (duration_minutes, status, group_id, teacher_id, branch_id)` partial | Availability overlap читает room/date/status/duration | `/crm/rooms/availability` | Размер индекса; write overhead на lessons | `create index concurrently if not exists lessons_room_active_overlap_idx on app.lessons (room_id, scheduled_at) include (duration_minutes, status, group_id, teacher_id, branch_id) where deleted_at is null and status <> 'cancelled' and room_id is not null;` |
| `app.lessons` | `(teacher_id, scheduled_at) include (duration_minutes, status, room_id, group_id, branch_id)` partial | Teacher conflict checks | create/edit lesson availability | Write overhead | `create index concurrently if not exists lessons_teacher_active_overlap_idx on app.lessons (teacher_id, scheduled_at) include (duration_minutes, status, room_id, group_id, branch_id) where deleted_at is null and status <> 'cancelled' and teacher_id is not null;` |
| `app.profiles` | expression or stored normalized phone | `listProfiles` и phone-link candidates не должны делать regexp per row | `/admin/profiles`, link-user flows | Expression-index brittle; лучше stored generated/backfilled column | Лучше использовать существующую phone-normalization миграцию/колонку, если есть; иначе добавить `phone_normalized` + trigger/backfill |
| `app.students` | `(profile_id) where deleted_at is null` | linked profile counts | `/admin/profiles` | Небольшой write overhead | `create index concurrently if not exists students_profile_active_idx on app.students (profile_id) where deleted_at is null;` |
| `app.teachers` | `(profile_id) where deleted_at is null` | linked profile counts | `/admin/profiles` | Низкий | `create index concurrently if not exists teachers_profile_active_idx on app.teachers (profile_id) where deleted_at is null;` |
| `app.staff_members` | `(profile_id) where deleted_at is null` | linked profile counts | `/admin/profiles` | Низкий | `create index concurrently if not exists staff_members_profile_active_idx on app.staff_members (profile_id) where deleted_at is null;` |
| `app.tasks` | `(entity_type, entity_id, status, due_at) where deleted_at is null` | Карточки клиента/лида и task sections | student/lead card task sections | Write overhead; проверить существующие индексы | `create index concurrently if not exists tasks_entity_status_due_active_idx on app.tasks (entity_type, entity_id, status, due_at) where deleted_at is null;` |

### Query Rewrites

1. `listProfiles`:
   - default: return id/user/role/name/phone/avatar/2fa only.
   - optional `includeCounts=true` для admin detail/modal.
   - counts считать batch CTE по `visible_profiles`, не correlated subquery per row.
   - phone candidate counts использовать stored normalized phone + indexed equality.

2. `listRoomAvailability`:
   - сначала `bounded_lessons as (...)` с date range и optional branch/room.
   - `room_conflicts` считать один раз по bounded set.
   - `is_available` считать через indexed bounded set, не full scan per room.

3. `getMySummary`:
   - отдельные narrow queries: `next_lessons limit 5`, `open_tasks limit 5`, `recent_payments limit 5`.
   - не использовать full operational list DTO.

## Backend Optimization Plan

1. Добавить request-level SQL metrics:
   - request id;
   - total SQL count;
   - total SQL time;
   - slowest SQL fingerprint;
   - payload bytes;
   - role/user anonymized id.
2. Для каждого key screen завести endpoint contract budget:
   - обычный list: p95 <= 500 мс, payload <= 100 KB;
   - heavy screen: p95 <= 1000 мс, payload <= 300 KB;
   - save mutation: p95 <= 800 мс.
3. Split DTO:
   - list DTO;
   - detail DTO;
   - optional expansions;
   - section endpoints.
4. HTTP caching:
   - branches/rooms/lead statuses/subscription packages/staff summary: `ETag` или `Cache-Control: private, max-age=300`.
   - Не кешировать RBAC, деньги и активные назначения без строгой инвалидации.
5. Mutation idempotency:
   - payments уже имеют guard;
   - добавить/request idempotency для task/lesson create или double-submit guard на frontend.

## Frontend Optimization Plan

1. Instrument Flutter profile builds:
   - network waterfall per tab;
   - time to first visible content;
   - time to full data;
   - provider invalidation graph;
   - rebuild counts for large widgets.
2. Tab opening model:
   - first paint: только critical data;
   - secondary blocks lazy;
   - section-level loading/error вместо global loading.
3. Riverpod/cache:
   - reference providers with TTL and stale-while-revalidate;
   - no requests in `build`;
   - no provider recreation on tab rebuild.
4. Lists:
   - server-side pagination/search/filter/sort;
   - `ListView.builder`/virtualization;
   - debounce search 250-400 мс;
   - no client-side filtering over 500+ rows for primary flow.
5. Saves:
   - disable submit while pending;
   - optimistic UI only for safe actions: chat send, local status marker, draft UI;
   - backend-confirmed UI for payments/subscriptions/RBAC-sensitive operations.

## Realtime Optimization Plan

| Сценарий | Событие | Payload | Local update | Refetch |
| --- | --- | --- | --- | --- |
| Chat message | `message.created` | message id/chatId/content/sender summary/timestamp | append/dedupe by id | Нет, кроме missing gap |
| Lesson changed | `crm.changed lesson` | id/action/branchId/affectedUserIds/version | update one lesson if loaded, invalidate day/week section | Только affected section |
| Payment created | `crm.changed payment` | id/action/studentId/affectedUserIds/version | update student finance summary if section active | Refetch finance section only |
| Task changed | `crm.changed task` | id/action/entity id/status/version | patch task board/list | Refetch board column only on gap |
| Lead/student changed | `crm.changed lead/student` | id/action/status/branchId/version | patch card/board item | Refetch page only on missing item |

Required changes:

1. Deduplicate event by `(entity, id, action, version/timestamp)`.
2. Avoid full tab reload after minor event.
3. Fallback polling only when socket disconnected or stale, not global 10-entity burst every 30 seconds.
4. Dispose subscriptions on page leave; assert no duplicate subscriptions in tests.

## Infrastructure Plan

Current server is not saturated. Do not upgrade before proving p95 bottleneck under load.

Actions:

1. Add Node event-loop delay metric and heap RSS trend.
2. Instrument `pg.Pool` wait count/wait time; current pool max 10 may be fine, but wait must be measured.
3. Review Caddy compression/keep-alive/HTTP2 settings; enable gzip/zstd/brotli only for JSON where CPU overhead is acceptable.
4. Postgres tuning candidate after validation:
   - `random_page_cost` closer to SSD reality, e.g. 1.1-1.5;
   - `effective_io_concurrency` > 1 on SSD;
   - keep `statement_timeout=30s` for app role.
5. Keep production logs structured but not chatty; current logs did not show crash during save baseline.

## Risks

1. Query rewrites can change RBAC visibility. Every optimization must keep backend authorization as source of truth.
2. Caching can leak data if cache key omits user/role/branch.
3. Optimistic UI can show false success for payments/subscriptions/role changes.
4. New indexes speed reads but slow writes and increase migration time.
5. Realtime patching can create duplicate/incorrect state without event id/version/dedupe.
6. Splitting endpoints can improve first paint but increase request count if not orchestrated carefully.

## Implementation Plan

1. Add performance observability, no behavior change:
   - backend request SQL count/time/payload metrics;
   - Flutter tab timing harness;
   - repeat baseline 20 iterations per role/screen for p50/p95.
2. Fix `/crm/rooms/availability`:
   - rewrite bounded CTE;
   - add validated partial indexes;
   - before/after EXPLAIN and live endpoint p95.
3. Fix `/admin/profiles`:
   - default lightweight list;
   - move link/candidate counts to optional expansion/detail;
   - use normalized phone storage/index.
4. Fix schedule first paint:
   - month summary endpoint/DTO;
   - lazy availability.
5. Fix students board:
   - server-side pagination/filters/sort;
   - smaller board DTO.
6. Fix client card and client cabinet:
   - main card first;
   - lazy sections;
   - specialized `/crm/me` summary query.
7. Fix Flutter reference caching and duplicate loads.
8. Fix realtime targeted invalidation and poll throttling.
9. Run role/security regression matrix.

## Test Plan

1. Backend:
   - unit tests for RBAC and DTO shape;
   - integration tests for key endpoints by role;
   - p95 benchmark harness with 20+ iterations per endpoint;
   - `EXPLAIN ANALYZE` before/after for rewritten SQL.
2. Database:
   - migration applies cleanly;
   - index usage verified;
   - no lock/deadlock/long migration risk;
   - `ANALYZE` after index/backfill.
3. Flutter:
   - profile build on Windows and Android;
   - network waterfall snapshots per tab;
   - provider invalidation/rebuild counts;
   - bad network profile with timeout/retry.
4. Realtime:
   - duplicate subscription test;
   - event dedupe/order test;
   - no full refetch on message/payment/task event unless gap detected.
5. Security:
   - role matrix: client/admin/manager/teacher/system_admin;
   - cache isolation by user/role;
   - no extra financial/staff fields to unauthorized roles.

## Acceptance Criteria

1. Ordinary tabs p95 <= 1000 мс first content.
2. Heavy tabs p95 <= 2000 мс full data.
3. Save mutations p95 <= 800 мс for simple forms; <= 1000 мс for lesson/payment/task.
4. `/admin/profiles` p95 <= 300-500 мс and SQL <= 150 мс or counts moved out of first paint.
5. `/crm/rooms/availability` SQL <= 50-150 мс for day range.
6. Month schedule payload <= 150-250 KB or split into summary/detail.
7. Students/lead lists paginated/lazy with no 500-row client-only primary board load.
8. Chat loads first page only, cursor pagination verified.
9. Student card first paint independent from finance/lessons/tasks secondary sections.
10. Realtime events patch targeted state; no duplicate subscriptions; no global tab reload.
11. RBAC unchanged; no private data in shared cache or realtime events.

## Questions Before Final Fixes

1. Какие вкладки сейчас субъективно самые медленные: расписание, ученики, лиды, карточка клиента, финансы, чат или dashboard?
2. Какие роли чаще всего жалуются: клиент, администратор, управляющий или преподаватель?
3. Какие экраны должны открываться почти мгновенно даже на слабом телефоне?
4. Какие данные можно показывать из кеша, а какие всегда должны быть строго актуальными?
5. Для расписания default range должен быть день, неделя или месяц?
6. Для чатов первый экран: 20, 30 или 50 сообщений?
7. Для клиентов/учеников/лидов какой page size приемлем: 25, 50 или 100?
8. Нужен ли offline/stale режим при плохом интернете?
9. Какие действия можно делать optimistic UI: чат, задачи, перенос карточек, attendance?
10. Какие действия нельзя показывать успешными до ответа backend: оплаты, абонементы, роли, назначения администратора?
