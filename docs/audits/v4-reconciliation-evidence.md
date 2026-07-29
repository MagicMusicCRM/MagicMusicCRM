# T8.1.5 — Reconciliation Harness Evidence

Проверка выполнена 2026-07-25 на реальном локальном PostgreSQL 16.4.
Harness создаёт только session-local temporary tables, а source/target
snapshot и сравнение выполняет в `REPEATABLE READ READ ONLY`.

## Именованные инварианты

| Invariant | Owner | Economic tolerance |
|---|---|---:|
| `finance.payment-facts` | SYS-COMMERCE | 0 |
| `finance.adjustment-facts` | SYS-COMMERCE | 0 |
| `finance.balance-facts` | SYS-COMMERCE | 0 |
| `commerce.subscription-facts` | SYS-COMMERCE | 0 |
| `schedule.lesson-facts` | SYS-SCHEDULE | 0 |
| `schedule.participation-facts` | SYS-SCHEDULE | 0 |
| `workflow.task-facts` | SYS-WORKFLOW | 0 |
| `access.role-mappings` | SYS-ACCESS | 0 |

Отчёт содержит source/target counts, SHA-256 digest каждого набора и
адресуемые по entity ID unexplained diffs. Суммы, PII и connection strings в
отчёт не попадают. Canonical report content подписывается Ed25519; публичный
ключ и проверенная подпись включены в JSON.

## Acceptance

```powershell
npm --prefix server run v4:reconcile -- --fixture clean
npm --prefix server run v4:reconcile -- --fixture drift --expect-fail
```

- Clean fixture: `8 → 8` facts, `0` invariant drift, `0` unexplained diff.
- Drift fixture: `8 → 9` facts, `1` invariant drift, `1` unexplained
  duplicate payment fact.
- Drift fixture без `--expect-fail`: exit code `1`.
- Live `app → app` extraction: `11 → 11` facts, drift `0`.
- SHA-256 полного persistent `pg_dump --data-only --column-inserts` до/после:
  `37287f7754b67345ea5fabb0c68043c5ec78ab1969ae1077d44ba6d46b7625f4`
  в обоих случаях.
- Report privacy scan: `0` private-shape matches.
- Signature/tamper unit tests: `2/2`.
- Backend typecheck/build: PASS.
- Полный backend regression: `103/103` suites, `929/929` tests.

## Артефакты

- `scripts/v4_reconcile.ps1`
- `scripts/fixtures/v4-reconcile-clean.sql`
- `scripts/fixtures/v4-reconcile-drift.sql`
- `docs/audits/v4-reconciliation-report.schema.json`
- `docs/audits/v4-reconciliation-clean.json`
- `docs/audits/v4-reconciliation-drift.json`
- `docs/audits/v4-reconciliation-app-to-app.json`
