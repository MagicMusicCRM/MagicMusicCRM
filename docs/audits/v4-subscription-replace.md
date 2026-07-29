# v4 T5.2.3 — Subscription replacement evidence

- Preview подписан HMAC на 5 минут и связывает actor, student, issued/package versions, used/future units, payments и reservation plan.
- Новый объём меньше использованного и замена между валютами отклоняются до записи.
- Confirm повторно блокирует и пересчитывает контекст в transaction boundary.
- Old subscription закрывается как `replaced`; создаётся ровно один новый immutable snapshot и один differential debt/overpayment fact при ненулевой разнице.
- Existing payments остаются неизменными; допустимые ранние резервы переносятся, overflow освобождается, active reservations на old subscription не остаются.
- Replay возвращает тот же внешний result, а cross-student и concurrent stale commands не создают фактов.
- Flutter client-card показывает полный preview, требует явный reason code и сохраняет mutation identity для безопасного retry.

Проверки:

- PostgreSQL replacement integration: `4/4`.
- Flutter replacement service/widget: `2/2`.
- TypeScript no-emit и `git diff --check`: PASS.
