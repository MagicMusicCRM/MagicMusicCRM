# V6-606 — Cross-app canonical navigation

**Дата:** 2026-08-07  
**Область:** Flutter production workspace; API/backend contracts unchanged.

## Результат

`ProductionWorkspaceHost` теперь владеет общим desktop rail, context tail и
typed navigation events. Поэтому long-lived окно не демонтирует основной
раздел и не создаёт второй независимый маршрут.

| Основной раздел | Каноническое содержимое |
|---|---|
| Чат | список чатов и выбранный typed chat |
| Расписание | расписание, занятие и desktop-редактор занятия |
| Клиенты | список, Lead/Student card и связанные клиентские оплаты |
| Задачи | общие и клиентские задачи |
| Аналитика | отчёты и разрешённые школьные финансы |
| Настройки | CRM-конфигурация, профиль сотрудника и управление доступом |

Старые `/crm/configuration`, `/admin/profiles/:id` и `/lessons/:id`
перенаправляются в role-aware workspace с сохранением section/entity/focus.
Переходы из расписания, клиента, чата и настроек больше не сбрасывают
пользователя на `/admin`. Auth/account flow, selection, quick-view и
confirmation остаются самостоятельными route/overlay только там, где это
является их фактической семантикой.

## Инварианты

- desktop: один `V7NavShell`, один context tail и одна история вкладки;
- compact: один GoRouter stack без дублирующего rail;
- forbidden user/config surface закрывается до загрузки данных;
- linked client payment остаётся в разделе «Клиенты»;
- typed chat открывает содержимое чата, а не только пункт меню;
- logout/role change по-прежнему очищает account-scoped workspace state.

## Проверки

- `flutter analyze` — PASS;
- `flutter test` — **623/623 PASS**;
- `flutter build windows --debug` — PASS;
- actual-surface/route/chat/access regression tests — PASS;
- UX inventory stale-check — PASS: routes **22**, reachable **254**,
  navigation callsites **256**, production workspace usages **2**, unowned **0**;
- `git diff --check` — PASS;
- `git diff --exit-code -- server/` — PASS (server diff empty).

Сгенерированные `v6-navigation-inventory`, `v6-route-surface-inventory` и
`v6-input-back-inventory` обновлены этим же кандидатом.
