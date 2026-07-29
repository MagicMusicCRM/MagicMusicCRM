# v4 T5.3.1 — Role-scoped commerce projection evidence

- `GET /crm/me/commerce` возвращает Client только собственные/семейные read-only commerce projections.
- `GET /crm/students/:studentId/commerce` возвращает Admin/Manager только branch-scoped client-card, Director — business-wide, system_admin — отдельный emergency scope.
- Teacher отклоняется до repository/SQL; finance/subscription keys, requests, realtime invalidations и exports для Teacher равны нулю.
- Global payments/subscriptions/balances/expected-payments доступны только Director/system_admin.
- Проекция читает immutable commercial snapshots, installments, `amount_minor`, obligation facts и lesson charge facts; mutable catalog price, legacy expected payments и attendance не используются.
- Client DTO исключает discount reason, source/audit/idempotency/internal fields; валюты считаются раздельно.
- Cache partitions разделены по projection profile, actor, access version, finance surface и resource scope.
- `finance.changed` использует отдельную room без Teacher, active Client-only user audience и payload только `{scope: "client-finance"}`.
- Flutter Client self и staff client-card используют scoped endpoints; Teacher не создаёт commerce provider и не показывает finance UI.

Точечные проверки:

- Core commerce projection contract: `11/11`.
- Access/realtime/service boundary: `48/48`.
- Flutter six-role contract: `3/3`.
- Единственный review-проход: найдено `3 High`, исправлено `3/3`, повторный аудит не выполнялся.

Единственный полный batch-прогон:

- Backend: `136` suites / `1119` tests, `0` skipped; четыре stale fixture/coverage assertions исправлены, три затронутые suites затем targeted PASS.
- Flutter: analyze clean; `430` tests, одна stale endpoint fixture исправлена и targeted `1/1` PASS.
- Backend typecheck/build: PASS.
- Неразрешённых regression failures: `0`.
- Lock/dependency changes: `0`.
