# INT-S3 — Subscription Integrity

Дата: 2026-07-30  
Статус: PASS

## Gate

- Все задачи SYS-COMMERCE S3 и обязательные evidence присутствуют.
- Commerce actor/concurrency regression: 8/8 suites, 35/35 tests.
- Actor Matrix и payload leak scan: 2/2 suites, 9/9 tests.
- Flutter catalog/issue/replace/cancel/finance surfaces: 17/17 tests.
- Backend typecheck: clean.

## Reconciliation

- Clean fixture: 10/10 invariants, 10 source facts = 10 target facts,
  unexplained drift = 0.
- Negative fixture: один дополнительный payment fact обнаружен как ровно
  один signed unexplained diff.
- Duplicate facts и успешные unauthorized mutations: 0.
- Replace/cancel сохраняют payments, revenue и historical Lesson facts.

Machine-readable result: `docs/audits/v4-s3-gate-result.json`.
