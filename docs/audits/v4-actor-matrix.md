# MagicMusicCRM v4 — Actor Matrix & Payload Leak Scan

**Task:** T2.4.1
**Result:** PASS
**Date:** 2026-07-30

## Route matrix

Матрица построена из versioned capability registry и актуального
`v4-access-coverage.json`, затем выполнена через production
`CapabilityRequestAuthorizer` на реальной PostgreSQL для шести seed actors.
Каждый из 268 private routes проверен как positive или negative для каждой
роли; resource-scope остаётся второй обязательной границей в domain
service/repository.

| Actor | Allowed | Denied | Total |
|---|---:|---:|---:|
| Client | 134 | 134 | 268 |
| Teacher | 138 | 130 | 268 |
| Admin | 230 | 38 | 268 |
| Manager | 246 | 22 | 268 |
| Director | 268 | 0 | 268 |
| system_admin | 268 | 0 | 268 |
| **Всего** | **1284** | **324** | **1608** |

Результат: 100% expected allow прошли, 100% expected deny вернули
`ForbiddenException`, unknown routes = 0, missing scopes = 0, unexplained
allows = 0.

## Teacher payload scan

Sentinel scan проверяет запрещённые keys и values до сериализации:

- client JSON;
- search read model;
- schedule read model;
- chat composition;
- export composition;
- safe CRM/access realtime payloads;
- structured logs после central redaction.

Запрещённые contacts, representatives, finance, subscriptions, payments,
balance, debt, price, cost, rate, phone, email и address отсутствуют.
Private comment sentinel также не проходит ни в одну Teacher projection.
Leak scan обнаружил и закрыл общий logging gap: central redaction теперь
маскирует financial, payment/subscription, comment/body и representative
поля как `[PRIVATE]`.

## Проверки

```powershell
npm --prefix server run test:actor-matrix:v4
npm --prefix server run typecheck
npm --prefix server test
npm --prefix server run build
pwsh -File scripts/v4_inventory.ps1 -Check
```

| Gate | Result |
|---|---:|
| Exact Actor Matrix + leak scan | 2/2 suites, 9/9 tests |
| Route decisions | 1608/1608 |
| Allowed / denied | 1284/1284 · 324/324 |
| Teacher payload leaks | 0 |
| Unknown routes / missing scopes | 0 / 0 |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 119/119 suites, 1053/1053 tests |
| Current-state inventory | 280 routes, 641 DTO fields, 0 unowned |
