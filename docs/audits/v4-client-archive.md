# MagicMusicCRM v4 — Client Archive Impact & Tombstone

**Task:** T3.2.3  
**Requirements:** REQ-CLIENT-002, REQ-AUDIT-001  
**Result:** PASS  
**Date:** 2026-07-25

## Реализованный контракт

- `POST /api/crm/clients/archive/preview` принимает typed `ClientRef` и
  возвращает текущую версию, warnings, blockers, linked navigation и impact.
- `POST /api/crm/clients/archive` требует `expectedVersion`,
  `confirm=true` и bounded reason code.
- Совместимый
  `POST /api/crm/clients/leads/:leadId/archive-source` использует тот же
  safe archive flow и дополнительно требует существующий `ConversionLink`.
- Только `director`/`system_admin` проходят domain policy; `admin` и
  `manager` получают `403`.

## Impact preview

Один PostgreSQL statement с CTE и batched scalar projections собирает:

- будущие незавершённые занятия;
- открытые задачи;
- активные абонементы;
- сохранённые платежи, ожидаемые платежи и операции личного счёта;
- активные user links и Lead ↔ Student conversion navigation.

Активные связи создают явные warnings. Они не удаляются и не меняются при
архивировании.

## Versioned archive boundary

Миграция `0082_client_archive_lifecycle` добавляет monotonic `version` в
`Lead` и `Student`, backfill-ит `aggregate_versions` и синхронизирует новые,
изменённые и hard-deleted test/import rows через PostgreSQL trigger.

Archive выполняется через Platform Integrity transaction:

1. проверяется active aggregate и `expectedVersion`;
2. ставится `deleted_at`, версия увеличивается;
3. атомарно записываются before/after/reason audit и минимальный
   `crm.client.archived` outbox event;
4. deterministic idempotency scope возвращает стабильный результат при retry.

Повтор уже завершённого archive возвращает текущий tombstone без второго
audit/outbox. `ClientReferenceService` проецирует `version`, `archivedAt` и
сохранившийся Lead ↔ Student navigation link.

## Проверки

| Gate | Result |
|---|---:|
| Exact PostgreSQL archive scenario | 1/1 |
| Conversion + ClientRef compatibility | 3/3 suites, 9/9 tests |
| Admin denied / Director confirm | PASS |
| Relations and finance facts preserved | PASS |
| Atomic audit + outbox, duplicate count | 1 + 1 |
| Migration `0082` down → up | PASS |
| Actor Matrix + payload leak | 2/2 suites, 8/8 tests |
| Route decisions | 1488/1488 |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 119/119 suites, 1053/1053 tests |
| Access coverage | 248/248 private routes |
| Current-state inventory | 260 routes, 564 DTO fields, 0 unowned |

Exact command:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/clients/archive-postgres.integration.spec.ts
```
