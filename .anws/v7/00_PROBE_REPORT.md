# MagicMusicCRM v7 — Deep Probe актуального client/server кода

| Поле | Значение |
|---|---|
| Дата | 2026-08-10 |
| Режим | Deep PROFILE → REASON → OBJECT → BENCHMARK → EMIT |
| Сценарий | Б — проверка реализации относительно `.anws/v7` |
| Кандидат | `1.5.1+179` |
| Карта | `.nexus-map/INDEX.md` |
| Решение | **STRUCTURAL MAP PASS; OWNER UAT IN PROGRESS** |

## 1. Системный отпечаток

Карта построена заново из текущего `main`, без исторических планов как источника
реализации. Большие machine-readable файлы находятся в `.nexus-map/inventory/`.

| Слой | Фактическое покрытие |
|---|---:|
| Flutter production files | 261 |
| Dart declarations | 4 354 |
| Именованные Widget classes | 378 |
| Dart methods / functions | 2 566 / 383 |
| Riverpod providers | 63 |
| GoRouter routes / production screens | 22 / 21 |
| Modal, sheet и drawer surfaces | 100 |
| Flutter API callsites | 280 |
| Server modules / classes / functions-methods | 768 / 397 / 2 315 |
| NestJS endpoints / DTO fields / policy calls | 321 / 801 / 245 |
| SQL migration files | 232 |

Общий AST содержит 1 281 файл, 4 269 nodes, `truncated=false`, parse errors=0.
Dart, отсутствовавший в structural queries generic mapper, дополнительно разобран
официальным analyzer; поэтому виджеты, методы и функции больше не теряются.

## 2. Runtime topology

1. `lib/main.dart` — Flutter/Riverpod/GoRouter client.
2. `server/src/main.ts` — NestJS HTTP/JSON + Socket.IO server.
3. PostgreSQL — источник истины для access, CRM, schedule, commerce и tasks.

Межпроцессные границы:

- Flutter → NestJS: HTTPS/JSON `/api` и Socket.IO `/realtime`;
- NestJS → PostgreSQL: repositories/transactions;
- Windows updater: `Process.start` в
  `lib/core/update/windows_update_service.dart`;
- synchronous security gate: `spawnSync` в
  `server/src/security/security-gate.ts`.

Backend DTO/policy boundary типизирован. Часть Flutter response decoding остаётся
map-shaped и требует Release UI smoke; статическая карта не заменяет UAT.

## 3. Client → server wire

| Класс связи | Количество | Значение |
|---|---:|---|
| Однозначно сопоставлено | 273 | verb/path соответствует одному endpoint |
| Dynamic dispatch | 3 | blacklist и lesson operation выбирают один из допустимых routes во время выполнения |
| External/transport dynamic | 2 | общий API transport и Windows update manifest |
| Unreferenced client method | 2 | legacy `updateAdjustment`/`voidAdjustment`, вызовов в `lib/` нет и backend-route отсутствует |

Эти две unreferenced записи не объявлены существующим функционалом. Они сохранены
в карте как явный dead-code факт, пока отдельная задача не разрешит их удаление.

## 4. Gap analysis

| ID | Разрыв | Состояние |
|---|---|---|
| MAP-01 | Generic Tree-sitter видел Dart только на уровне файлов | Закрыт Dart analyzer inventory |
| MAP-02 | Backend inventory использовал первый `@Controller` для всего файла | Закрыт nearest-controller parsing + regression check |
| MAP-03 | Два client adjustment метода не имеют callers/server routes | Явно помечены `unreferenced_client_method`, не production functionality |
| MAP-04 | Старые v4/v6 имена генераторов могут выглядеть как версия продукта | В активной `.nexus-map` используются только фактические строки; legacy status отброшен |
| MAP-05 | Static code presence может быть ошибочно принято за готовность | Owner UAT остаётся отдельным открытым gate |

Архитектурные владельцы текущего кода согласуются с v7: App Experience, Access
Scope, CRM Workspace, Schedule, Commerce Integrity, Operations, UI Foundation и
Platform Quality. Необъяснённых route/surface/inventory owners: 0.

## 5. Risk matrix

| Риск | Критичность | Контроль |
|---|:---:|---|
| Карта устаревает после изменения production source | Высокая | source digest + inventory `-Check` перед кодингом |
| Агент загружает многомегабайтный JSON целиком | Средняя | `INDEX.md` требует точечный `rg`/PowerShell query |
| Dynamic route ошибочно принят за отсутствующий endpoint | Средняя | `wire_matrix.json` хранит все candidates и status |
| Dead client method принят за доступную функцию | Средняя | отдельный `unreferenced_client_method` status |
| Static PASS принят за owner acceptance | Высокая | `T7.1.2`/`INT-S6` и UAT result остаются открыты |

## 6. Проверки

- `scripts/v4_inventory.ps1 -Check` — PASS, routes=321, unowned=0.
- `scripts/v6_ux_inventory.ps1 -Check` — PASS, routes=22, reachable=260,
  unowned=0.
- `scripts/v7_commerce_schedule_inventory.ps1 -Check` — PASS, finance=256,
  lesson writes=7, unowned=0.
- Dart mapper analyze — no issues.
- JSON/path/concept validation — PASS.
- AST — `truncated=false`, parse errors=0.

## 7. Решение

Структурная карта пригодна как актуальная память будущих агентов. Она не меняет
статус production mega-UAT: текущая 100-строчная матрица остаётся открытой и
является единственным источником owner acceptance.
