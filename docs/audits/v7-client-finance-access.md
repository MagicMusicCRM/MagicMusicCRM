# v7 — T2.1.5 Client-finance access, projections and audit

**Дата:** 2026-08-07  
**Статус:** PASS

## Реализованный контракт

- Production client-finance mutations используют `commerce.client_finance.write`; legacy issue routes остаются явно привязаны к `commerce.subscription.issue`.
- Каждая commerce-команда повторно читает текущую capability внутри той же PostgreSQL-транзакции до idempotency reservation и денежных фактов. User и active role package удерживаются shared-lock до commit.
- Recipient и payer проверяются одним branch-scoped repository path и блокируются в стабильном UUID-порядке. Чужой UUID возвращает actor-safe `404`.
- Каталог абонементов дополнительно проверяет `config.commerce.manage` непосредственно в mutation transaction.
- Migration `0108_v7_client_finance_audit` добавляет отдельный trimmed `reason_text` длиной 1..500 и индекс bounded operational-history lookup. Down fail-closed, если удаление уничтожило бы причины.
- Risky purchase/payment/status/reversal/replacement/cancel/adjustment команды пишут stable reason code и отдельный human reason. Секреты и финансовые/PII поля не попадают в result/outbox/log envelopes.
- Client projection не материализует technical history и не получает внутренний comment; staff history ограничена 200 строками. Teacher блокируется до finance query.
- Admin/Manager сохраняют scoped client-card finance, но school finance и commerce configuration им запрещены. Director/system_admin имеют разрешённые business/config projections.

## Проверки

| Gate | Результат |
|---|---:|
| Migration `0108` down → up | PASS |
| Commerce integration | 8/8 suites, 57/57 tests |
| Preview → revoke capability → commit | denied, business writes = 0 |
| Actor Matrix + payload leak | 2/2 suites, 9/9 tests |
| Full backend | 152/152 suites, 1188/1188 tests |
| TypeScript typecheck / Nest build | PASS / PASS |
| v7 commerce reconcile | issues = 0 |
| v4 signed reconciliation | drift = 0, signature valid |
| Route access coverage | 280/280 private routes, unexplained allow = 0 |
| v7 inventory | finance = 243, lesson writes = 13, unowned = 0 |

## Вывод

Критерии T2.1.5 выполнены: разрешённые staff-роли могут менять только доступные им client-finance aggregates, отозванные права не переживают открытый preview, запрещённые роли не получают скрытые payload/request paths, а человеческие причины сохраняются отдельно от технических кодов.
