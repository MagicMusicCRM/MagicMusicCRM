# v7 INT-S1 — Client Commerce

**Дата:** 2026-08-07  
**Статус:** PASS

## Принятый end-to-end контур

| Цепочка | Проверенный результат |
|---|---|
| Purchase с личного счёта другого клиента | Явные recipient/payer/reason, полная сумма блокируется и списывается один раз, оба client scopes обязательны |
| Purchase в рассрочку | Полное обязательство резервируется сразу, график частей точный, выдача не создаёт ложную выручку |
| Payment lifecycle | Ровно `unpaid`, `pending_verification`, `paid`; pending не влияет на баланс, unpaid учитывается как долг, paid создаёт один ActualPayment |
| Reversal / technical void | Paid получает равную обратную проводку; pending/unpaid — только техническое исключение; ordinary reporting не считает обе стороны |
| Cancel / refund | Возврат идёт исходному payer, учитывает funded/unfunded, usage/reservations/prior refunds и создаётся не более одного раза |
| Access / audit | Admin/Manager/Director — только scoped client finance; Teacher/Client denied; school finance/config не утекают; отзыв capability до commit блокирует все записи |

## Инженерные доказательства

- Migrations `0103..0108` применены; `0108` отдельно прошла `down → up`.
- `npm run test:commerce-v4`: **8/8 suites, 57/57 tests**.
- `npm run test:actor-matrix:v4`: **2/2 suites, 9/9 tests**.
- Полный backend: **152/152 suites, 1188/1188 tests**.
- `npm run typecheck`: PASS.
- `npm run build`: PASS.
- `npm run v4:preflight -- --check-read-only` дважды: **19/19 checks, findings=0**, одинаковый digest `267c1cce8fb5635640c69e2b3e95a7b96a21ec04e1266240b7cdb18244010090`.
- `npm run v7:reconcile` дважды: `issues=[]` в обоих запусках.
- Signed v4 reconciliation: **17 invariants, drift=0, signature valid**.
- Route access coverage: **280/280**, unexplained allow = 0.
- Inventory: **finance=243, reporting-safe=51, lesson writes=13, unowned=0**.

## Итог

Sprint S1 принят. Атомарность, идемпотентность, три статуса оплаты, reporting exclusions, cancel/refund, recipient+payer scope, role projection и human audit reasons подтверждены единым PostgreSQL-backed gate. Открытых дефектов S1 нет.
