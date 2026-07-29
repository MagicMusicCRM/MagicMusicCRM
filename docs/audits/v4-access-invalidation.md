# MagicMusicCRM v4 — Access & Session Invalidation

**Task:** T2.3.2
**Result:** PASS
**Date:** 2026-07-25

## Реализация

- Access mutations сохраняют `accessVersion` в redacted platform outbox вместе
  с audit и domain write в одной PostgreSQL-транзакции.
- После успешного commit (и только не-idempotent replay) сервер публикует
  безопасный `access.invalidated`:
  - user role/override change — в `user:{userId}`, поэтому событие получают все
    вкладки и окна аккаунта;
  - role package change — всем authenticated sockets, чтобы сессия со старой
    JWT-role тоже не пропустила invalidation.
- Payload ограничен `{accessVersion, scope}` и не содержит role, email, имени,
  capability diff или иных business/PII данных.
- Flutter использует общий ref-counted Socket.IO transport, сбрасывает
  `releaseGateStatusProvider` и повторно проверяет текущий route через router.
- Следующий REST-запрос независимо от realtime/UI заново читает текущие
  role package и personal override из PostgreSQL в capability guard.
- `system_admin` account/role скрыт из profile/staff business lists для всех
  ролей, кроме самого `system_admin`; emergency root API остаётся отдельным.

## Доказательство двух сессий

`access-invalidation.integration.spec.ts` создаёт Director и Manager в реальной
PostgreSQL, открывает две независимые подписки одного Manager, затем Director
устанавливает personal deny для `report.status.read`.

Обе подписки:

1. получают `access.invalidated` с `accessVersion=2`;
2. очищают видимость control;
3. выполняют следующий request через production
   `CapabilityRequestAuthorizer`;
4. получают `ForbiddenException`.

Измеренный путь выполняется существенно быстрее лимита 5 секунд. Тест также
проверяет committed access version, единственный audit и безопасный outbox
payload.

## Проверки

```powershell
npm --prefix server test -- --runTestsByPath src/access-control/access-invalidation.integration.spec.ts
npm --prefix server run typecheck
npm --prefix server test
npm --prefix server run build
flutter analyze
flutter test
```

| Gate | Result |
|---|---:|
| Exact PostgreSQL + two-session invalidation | 1/1 |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 111/111 suites, 1028/1028 tests |
| Flutter analyze | No issues found |
| Full Flutter regression | 401/401 tests |
