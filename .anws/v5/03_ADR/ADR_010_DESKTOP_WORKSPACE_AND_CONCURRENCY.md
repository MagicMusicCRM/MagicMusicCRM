# ADR-010 — Account-scoped desktop workspace и конкурентность вкладок

**Status:** Accepted  
**Date:** 2026-07-25  
**Influence scope:** SYS-APP, SYS-ACCESS, SYS-PLATFORM  
**Requirements:** REQ-NAV-001, REQ-NAV-002, REQ-NAV-003, REQ-RBAC-001

## Context

Windows-версия должна поддерживать до 10 внутренних вкладок, открытие связанной записи через меню с троеточием, drag-and-drop и восстановление рабочего пространства. Несколько вкладок одного аккаунта не должны расходиться по авторизации и доменному состоянию. На мобильном требуется обычный navigation stack.

## Decision

1. Вкладка — tab-local route stack и form state; auth session, API cache, capability snapshot и realtime connection общие для окна приложения.
2. Persistence namespace включает account id и schema version. При logout все вкладки и persisted workspace данного аккаунта очищаются до показа login.
3. Одна entity может быть открыта в нескольких вкладках; каждая хранит только entity reference и последнюю server version.
4. Committed realtime invalidation обновляет общий cache. Вкладка без dirty form перезагружается; dirty form показывает conflict banner и не затирает ввод.
5. Write-команды используют aggregate version и idempotency key. Stale write возвращает typed conflict и актуальную server version.
6. Закрытие dirty-вкладки требует `Save / Discard / Cancel`.
7. Лимит — 10 вкладок на desktop workspace; при достижении новая вкладка не создаётся, пользователь получает явный выбор существующей/закрытия.
8. Hover ellipsis предоставляет `Открыть в новой вкладке`, `Дублировать`, `Закрыть`, `Закрыть другие`; D&D меняет только порядок.
9. Мобильное приложение не рендерит tab strip и использует typed navigation stack с теми же context links.

## Options considered

| Option | Плюсы | Минусы | Решение |
|---|---|---|---|
| Полностью независимый provider scope на вкладку | Простая изоляция форм | Дубли auth/socket/cache, расхождение прав | Отклонено |
| Один глобальный route/form state | Простая синхронизация | Вкладки перетирают друг друга | Отклонено |
| Shared session/cache + tab-local navigation/forms | Изоляция UX и единая истина | Нужен conflict protocol | Принято |

## Consequences

- Tab serialization хранит ссылки, не чувствительные DTO.
- Workspace не синхронизируется между разными аккаунтами или устройствами.
- Logout/access invalidation имеет приоритет над unsaved state.
- Domain mutations остаются серверными; вкладки не используют локальный last-write-wins.

## Verification

- Widget tests покрывают limit, D&D, context menu, dirty-close и restore.
- E2E с двумя вкладками проверяет stale conflict и последующее обновление.
- Logout в одной активной поверхности приводит все tab routes к login.
- Android golden/navigation tests подтверждают отсутствие desktop tab UI.

## Design links

- `04_SYSTEM_DESIGN/app_workspace.md`
- `04_SYSTEM_DESIGN/platform_integrity.md`
- `04_SYSTEM_DESIGN/access_control.md`
