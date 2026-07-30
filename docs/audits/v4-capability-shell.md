# T1.1.1 — Capability-driven Flutter shell

Дата: 2026-07-30

## Реализация

- `GET /access/me` возвращает effective capability snapshot, account id, access version и actor scopes.
- Маршрут собственного snapshot является authenticated-only: personal deny не
  может заблокировать перечитывание server truth после invalidation.
- Flutter snapshot key: `accountId:accessVersion`; неизвестное capability трактуется как deny.
- CRM destinations вычисляются из server-sourced capabilities, а не из имени роли.
- `access.invalidated` сбрасывает snapshot до refetch; новый access version пересоздаёт shell boundary и очищает локальное чувствительное состояние.
- Обычный business UI не получает emergency/root surface только из названия роли.

## Проверки

- `capability_shell_test.dart`: 3/3.
- Backend capability route policy: 34/34.
- Backend typecheck: clean.
- Existing two-session invalidation contract: ≤5 s.
