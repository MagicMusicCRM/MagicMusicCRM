# T1.2.4 — Workspace persistence и global logout

- Workspace хранится отдельно по `accountId` и schema version.
- Сериализация включает только route refs, filters/date/scroll, active tab и порядок.
- DTO, токены, form registry и dirty draft values не сохраняются.
- Restore проверяет schema/account, поддержку route и актуальный capability predicate; при любой ошибке используется safe fallback.
- Logout coordinator синхронно очищает все workspace-контроллеры аккаунта и удаляет persisted snapshot.

## Проверка

- `flutter test test/features/v4/workspace_persistence_logout_test.dart` — 4/4 PASS.
- Регрессия desktop workspace controller — 4/4 PASS.
- Targeted Flutter analyze — PASS.
