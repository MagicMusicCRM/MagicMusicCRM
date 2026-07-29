# ADR-007 — Capability-пакеты, персональные overrides и privacy projections

**Status:** Accepted  
**Date:** 2026-07-25  
**Influence scope:** SYS-ACCESS, SYS-APP, все backend domain modules  
**Requirements:** REQ-RBAC-001, REQ-RBAC-002, REQ-PRIV-001, REQ-AUDIT-001

## Context

Простая проверка имени роли не выражает утверждённую модель: роль задаёт готовый пакет, Директор может точечно включать/выключать разрешения, Управляющий не может менять роли и доступы, преподавателю запрещены контакты и финансы клиента, а `system_admin` должен иметь аварийный полный доступ, оставаясь скрытым в бизнес-интерфейсе.

Если персональные overrides применять без ограничений, галочкой можно случайно вернуть преподавателю управление посещаемостью или дать Управляющему назначение ролей. Если фильтровать только UI, запрещённые поля останутся доступны через API.

## Decision

1. Сервер хранит versioned capability registry и role packages.
2. Effective access вычисляется сервером: `hard deny/allow invariant → role package → personal override → resource scope`.
3. Hard invariants нельзя изменить персональной галочкой:
   - `system_admin` получает все capabilities;
   - только `director` и `system_admin` управляют ролями и персональными overrides;
   - назначить `system_admin` через бизнес-интерфейс нельзя;
   - `system_admin` может назначить любую роль через emergency surface, но последнего активного `system_admin` нельзя деактивировать или понизить;
   - Teacher не изменяет занятие, посещаемость или завершение;
   - Teacher не читает контакты, платежи, баланс или абонемент клиента;
   - Teacher видит комментарий только при явном `sharedWithTeacher=true`.
4. API строит actor-aware projection и физически исключает запрещённые поля.
5. Session содержит не полный список прав, а идентичность и `accessVersion`; effective snapshot загружается отдельно и инвалидируется после изменения.
6. Flutter использует snapshot для навигации и affordance, но сервер повторно проверяет каждую операцию.
7. Каждое изменение роли/override пишет before/after audit с actor, target, reason и request id.
8. Смена роли атомарно сбрасывает персональные overrides после явного предупреждения.

## Options considered

| Option | Плюсы | Минусы | Решение |
|---|---|---|---|
| Set-based проверки ролей | Минимум изменений | Не поддерживают overrides и privacy fields | Отклонено |
| Полностью произвольные ACL | Максимальная гибкость | Сложно объяснить, легко нарушить инварианты | Отклонено |
| Role packages + overrides + invariants | Понятные шаблоны и точечные исключения | Нужны registry/version/matrix tests | Принято |

## Consequences

- Capability names становятся versioned contract.
- Любой новый endpoint обязан указать capability и projection policy.
- UI не показывает `system_admin` как обычную бизнес-роль.
- Access change может мгновенно закрыть экран или заменить данные безопасным состоянием.
- Необходима миграция существующих ролей в пакеты без расширения доступа.

## Verification

- Actor matrix покрывает Client, Teacher, Admin, Manager, Director и `system_admin`.
- Direct API tests доказывают отсутствие запрещённых teacher-полей в JSON.
- Manager получает `403` при role/override mutation; Director не может назначить `system_admin`; `system_admin` проходит все разрешённые domain operations.
- Две активные сессии получают access invalidation после изменения.

## Design links

- `04_SYSTEM_DESIGN/access_control.md`
- `04_SYSTEM_DESIGN/app_workspace.md`
- `04_SYSTEM_DESIGN/platform_integrity.md`
