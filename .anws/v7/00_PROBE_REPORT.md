# 🔎 MagicMusicCRM v6 — Deep Probe перед полным feature/UAT loop

| Поле | Значение |
|---|---|
| Дата | 2026-08-06 |
| Режим | Deep PROFILE → REASON → OBJECT → BENCHMARK → EMIT |
| Объём | Flutter + NestJS + PostgreSQL + Windows/Android runtime boundaries |
| Источники | свежий AST/Git probe, production inventories, route/service/runtime tracing |
| Решение | **кодовая поверхность покрыта; user-story acceptance ещё не завершена** |

## 1. Executive conclusion

Предыдущий probe устарел: перечисленные там разрывы production mounting были закрыты в v6/S1–S6. В текущем коде подключены desktop workspace, adaptive surfaces, явные scroll/input contracts, канонические Client/Lesson/Task routes, bounded client calendar, единый Dashboard и единая CRM Configuration с reusable field option sets.

Структурная полнота подтверждена: все production routes, surfaces, navigation sites и service calls имеют владельца. Однако зелёные инженерные suites не означают, что каждая функция реально пройдена пользователем. Текущий незакрытый риск — отсутствие единого story-level журнала `код → ожидаемое поведение → реальное исполнение → ошибка → исправление → повторный прогон`.

## 2. Свежая карта

| Метрика | Результат |
|---|---:|
| AST files / parse errors | 1,202 / 0 |
| Flutter production routes / screens | 22 / 22 |
| Production-reachable Flutter files | 253 |
| Production modal/surface calls | 93 |
| Production navigation sites | 263 |
| Production wire calls | 264 |
| Unowned entries | 0 |
| Git commits / authors (180 дней) | 723 / 5 |

Единственный inventory false-positive — conditional `runtime_env_io.dart`; это platform selection, не потерянная feature surface.

## 3. Production systems

| Система | Проверенное назначение | Главный acceptance-риск |
|---|---|---|
| Session & Account | login/signup/OTP/MFA/recovery/onboarding/legal/profile/deletion | реальная смена аккаунтов и очистка старой session/realtime state |
| App Experience | RBAC nav, typed links, tabs, Back, adaptive surfaces | role/deep-link/Back/restart matrix |
| Messenger | direct/group/channel chat, files, reactions, pins, read/presence | reconnect, late events и роль/room scope |
| CRM Clients | Lead/Student search, funnels, cards, conversion/archive | ввод поиска без rebuild/reset; correct actor projection |
| Schedule | Month/Week/Day, conflicts, lesson lifecycle, attendance | search highlighting, branch/timezone and concurrency |
| Commerce | catalog, subscription snapshot, payment, ledger, replacement/cancel | immutable history and permission scope |
| Shared Tasks | audience preview, links, reminders, history, close | preview reconciliation and linked navigation |
| Dashboard | one filter state, sections, drilldowns, exports | school-finance non-request for forbidden actors |
| Configuration | organization/schedule/CRM/options/catalog/access/data | effective school/branch revisions and fail-closed capabilities |
| Platform Quality | health, notifications, realtime invalidation, Windows update | lifecycle recovery and release artifact provenance |

## 4. Runtime inspector

### Process roots

1. `lib/main.dart` запускает Flutter/Riverpod/GoRouter, health warmup, push, session-gated realtime and Windows update check.
2. `server/src/main.ts` запускает NestJS with strict validation, safe exception/logging boundary, shutdown hooks, `/api`, CORS and HTTP/Socket.IO.

### Spawn chains

| Parent | Child | Проверка | Contract |
|---|---|---|---|
| Windows updater | PowerShell broker | encoded command, timeout/kill, captured output/exit, hash + PID + receipt validation | Strong |
| Security gate | local CLI | `shell: false`, synchronous exit/stdout/stderr capture | Strong |

### IPC / trust boundaries

- REST is **mixed-strength**: server DTO/policy/DB boundary is strong; several Flutter responses remain map-decoded.
- Realtime is **mixed-strength**: client events are DTO/rate/policy checked and server event names are explicitly allowlisted; Flutter payloads are still maps.
- Account replacement is explicitly guarded: realtime transport is reset before tokens change, subject mismatch disposes the old socket, reconnect obtains a fresh token.
- CRM/finance/access events are invalidation hints; values are refetched through authorized projections.
- Production realtime CORS fails closed without an allowlist.

## 5. Risk matrix

| ID | Риск | Вероятность | Влияние | Проверка в UAT loop |
|---|---|---:|---:|---|
| R1 | сохранённая сессия/сокет мешает повторному входу или переносит старый аккаунт | medium | critical | последовательный login/logout/same+other account/restart for all personas |
| R2 | search field теряет focus/value из-за rebuild/refetch | medium | high | ввод ФИО посимвольно в Leads/Students/Chat/Schedule |
| R3 | calendar search не даёт устойчивой зелёной/серой иерархии | medium | high | Month/Week/Day exact/non-match/clear filter |
| R4 | map-shaped payload drift проявится только runtime | medium | high | реальный backend for every service-backed story |
| R5 | forbidden role создаёт скрытый finance/config request | low | critical | network/log assertion for Client/Teacher/Admin/Manager |
| R6 | high-churn CRM/client/schedule seams regress | high | high | prioritize cross-navigation and mutations, then full retest |
| R7 | owner acceptance mistakenly inferred from green tests | high | high | separate Implementation Status from Test Status in canonical XLSX |

## 6. Git forensics

Самые изменяемые продуктовые seams за 180 дней: `crm.service.ts` (106), `client_card.dart` (67), `messenger_screen.dart` (60), `leads_widget.dart` (56), `schedule_widget.dart` (47), `crm.module.ts` (45), Flutter CRM service (41), tasks (35), reports (29) and router (28). Coupling `crm.service.ts ↔ spec` = 0.968, `crm.service.ts ↔ controller` = 0.960.

Это не основание переписывать систему. Это порядок тестирования: auth switching → typed search → calendar filtering → client workspace links → finance/subscription mutations → realtime reconnect → scoped dashboard/config.

## 7. Decision and next gate

### PASS

- production surface ownership;
- current architecture/runtime map;
- engineering regression evidence already recorded for v6/S6.

### OPEN

- story-level execution on real accounts and target platforms;
- error inventory, root-cause fixes and complete post-fix retest.

Следующий обязательный артефакт — один канонический XLSX. Он является единственным реестром user stories, expected behavior, execution evidence and errors. Release acceptance запрещено выводить только из source presence или aggregate green suites.
