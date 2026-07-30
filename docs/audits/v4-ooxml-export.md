# T7.2.1 — Валидный OOXML export

Дата: 2026-07-30

## Результат

- Подключён server-side ExcelJS builder для настоящих OOXML `.xlsx`.
- Workbook структурно перечитывается независимым validation pass до выдачи.
- Unicode, даты, денежные форматы и formula cells сохраняют корректные типы.
- До 10 000 строк export выполняется синхронно; 10 001–100 000 — через private async job.
- Более 100 000 строк отклоняются с требованием сузить фильтр.
- Async status/download доступны только создавшему job пользователю и истекают через 24 часа.
- CSV и XLSX получают корректные расширения и MIME; legacy finance façade теперь выдаёт `.xlsx`.

## Проверка

- PostgreSQL/OOXML integration: 1/1 suite, 3/3 tests.
- Streaming fixture: 10 001 строк, private download PASS.
- External OOXML validator: `OOXML PASS`.
- Migration `0093` down→up: PASS.
- Current-state inventory: 287 routes, 658 DTO fields, 0 unowned.
- Access coverage: 275/275 private routes, missing scope/unexplained allow = 0/0.
- Actor Matrix/payload leak: 2/2 suites, 9/9 tests.
- TypeScript typecheck: clean.
- Full backend regression/build: 144/144 suites, 1140/1140 tests, PASS.
- Full Flutter regression/analyze: 449/449 tests, PASS.

Один финальный regression выявил stale assumption в тесте миграции SharedTask:
он откатывал просто последнюю миграцию вместо целевой `0092`. Fixture сделан
version-aware и после точечного исправления весь пакет прошёл без ошибок.
