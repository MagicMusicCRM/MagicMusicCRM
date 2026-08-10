> generated_by: nexus-mapper v2 + project exhaustive inventories
> verified_at: 2026-08-10T14:11:29.427591+00:00
> source_revision: 13a9734356eca27f3d7b60dec00c639f1d85264b
> source_digest_sha256: cc6c200f55daa66889d4cd3a5de0176abe3d95eaf450576addb0db652f42a15f
> provenance: untruncated AST, Dart analyzer, route/DTO/policy/schema inventories and Git forensics

# MagicMusicCRM current code map

Один Flutter Windows/Android клиент работает с одним NestJS/PostgreSQL backend.
Карта построена только из текущего дерева `main`; исторические планы не являются
источником реализации.

## Покрытие

- Flutter: 261 файлов, 378 именованных виджетов, 2566 методов, 383 функций, 63 providers.
- UI: 22 routes, 21 production screens, 100 modal/sheet/drawer surfaces.
- Server: 321 endpoints, 397 classes, 2315 functions/methods, 801 DTO fields, 245 policy calls.
- AST: 1281 файлов, 4269 nodes, `truncated=false`, parse errors=0.
- Wire: 280 client calls; 273 literal route matches; remaining rows explicitly classified.

## Read next

- `inventory/README.md` — маршрутизация по исчерпывающим JSON.
- `arch/systems.md` — границы систем и владельцы.
- `arch/dependencies.md` — runtime/wire topology.
- `arch/test_coverage.md` — доказанное покрытие и белые пятна.
- `hotspots/git_forensics.md` — change-risk hotspots.

## Инструкция по эксплуатации

Перед изменением кода найти сущность в `inventory/feature_ownership.json`, затем
проверить точную декларацию в `flutter_code.json` или `server_code.json` и связь
в `wire_matrix.json`. Не загружать целые JSON в контекст: выбирать строки через
`rg`, `jq` или PowerShell. Если source digest не совпадает с рабочим деревом,
сначала регенерировать карту. `source_revision` может предшествовать map-only
коммиту и не является stale-признаком сам по себе.
