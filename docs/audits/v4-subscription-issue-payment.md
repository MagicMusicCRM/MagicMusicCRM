# v4 T5.2.2 — Subscription issue and payment evidence

- Issue создаёт immutable commercial snapshot, installments, obligations, lifecycle, audit и outbox в одной idempotent transaction.
- `8000 ₽ − 20% = 6400 ₽`; fixed discount поддержан; причина обязательна; final неотрицателен.
- Рассрочка содержит минимум две положительные части и в точности равна final price.
- Issue не создаёт revenue. ActualPayment записывается отдельной append-only cash/cashless командой; одинаковый retry возвращает тот же факт.
- Admin, Manager, Director и system_admin разрешены; Teacher и Client отклоняются.
- Flutter client-card фиксирует payload, дату и idempotency identities после первой попытки, поэтому повтор безопасен.

Проверки:

- PostgreSQL + capability contracts: `32/32`.
- Flutter issue form + client-card regression: `7/7`.
- Targeted TypeScript/Flutter analyze и `git diff --check`: PASS.
