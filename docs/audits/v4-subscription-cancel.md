# v4 T5.2.4 — Subscription cancellation evidence

- Preview подписан и связывает actor, student, issued version, payments, write-offs, balance и будущие занятия/резервы.
- Confirm повторно блокирует и пересчитывает контекст перед записью.
- Issued subscription атомарно переходит в `cancelled`; все активные future reservations освобождаются.
- Future lessons сохраняются.
- Payments, revenue, debt, obligations, write-offs, lesson snapshots и исторические факты не создаются и не изменяются.
- Единственные новые записи — subscription lifecycle, audit и minimal outbox.
- Concurrent stale replace/cancel допускает только одного победителя; idempotent replay возвращает тот же result.
- Flutter preview требует явный reason code, сохраняет mutation identity и обновляет карточку после успеха.

Проверки:

- PostgreSQL cancellation integration: `3/3`.
- Flutter cancellation service/widget: `2/2`.
- TypeScript no-emit и `git diff --check`: PASS.
