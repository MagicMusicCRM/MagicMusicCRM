# V4 Commerce actor/concurrency/reconciliation — T5.4.1

## Gate

`test:commerce-v4` объединяет schema, catalog, issue/payment, replace, cancel, Lesson race, settlement и role-scoped projection suites.

| Проверка | Результат |
|---|---:|
| Commerce regression | 8/8 suites, 35/35 tests |
| Actor Matrix + payload leak | 2/2 suites, 9/9 tests |
| Commerce reconciliation | 10/10 named invariants, drift 0 |
| Negative drift fixture | 1 unexplained diff обнаружен |
| TypeScript typecheck | PASS |
| Skipped tests | 0 |

## Доказанные инварианты

- Catalog management остаётся только Director/system_admin; active catalog и lifecycle commands следуют утверждённой role matrix.
- Повторные issue/payment/replace/cancel/completion requests не создают duplicate economic facts.
- Replace/cancel не создают ActualPayment и не меняют существующие payment/lesson facts.
- Completion vs cancel/replace сериализуется, reservation coverage остаётся согласованным.
- Reconciliation сравнивает payments, balances, issued snapshots, installments, obligations, lifecycle, Lesson client/teacher facts и reservations.
- Clean fixture: `10` source facts = `10` target facts, unexplained drift `0`.
- Drift fixture намеренно добавляет один payment fact и gate обнаруживает ровно `1` unexplained diff.

Подписанные отчёты:

- `docs/audits/v4-reconciliation-commerce-clean.json`
- `docs/audits/v4-reconciliation-commerce-drift.json`

Команды:

```text
npm --prefix server run test:commerce-v4
npm --prefix server run v4:reconcile -- --scope commerce --require-zero
```
