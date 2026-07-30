# T1.1.2 — Director access editor и emergency root surface

Дата: 2026-07-30

## Реализация

- Manager/Admin/Teacher/Client получают zero access-management controls.
- Director видит только пользователей и назначаемые роли строго ниже себя; `system_admin` account/filter/option скрыты.
- `system_admin` использует явно помеченный emergency surface и может назначать все роли.
- Редактор показывает package version/value, personal override и effective checkbox.
- Смена роли требует reason и явного подтверждения сброса overrides.
- Role/override writes используют expected access version и стабильную mutation identity.
- `409` не применяет optimistic state: редактор перечитывает server truth и показывает конфликт.

## Проверки

- `access_editor_roles_test.dart`: 4/4.
- Access mutation PostgreSQL: 6/6.
- Backend typecheck: clean.

