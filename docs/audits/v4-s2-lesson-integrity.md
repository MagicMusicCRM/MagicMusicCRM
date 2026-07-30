# INT-S2 — Lesson Integrity

Дата: 2026-07-30  
Статус: PASS

## Gate

- Все задачи S2 и обязательные evidence присутствуют.
- Schedule lifecycle/concurrency: 9/9 suites, 25/25 tests.
- Actor Matrix и payload leak scan: 2/2 suites, 9/9 tests.
- Flutter lesson/conflict/palette/Teacher surfaces: 16/16 tests.
- Backend typecheck: clean.

## Инварианты

- Create/edit/drag/series используют единый constraint path.
- Attendance mutation routes и controls: 0.
- Teacher calendar остаётся assigned-only и read-only.
- Два completion worker создают один terminal Lesson, один client fact,
  один teacher compensation fact и один audit/outbox.
- Completion latency contract: не более 60 секунд после `endAt`.

Machine-readable result: `docs/audits/v4-s2-gate-result.json`.
