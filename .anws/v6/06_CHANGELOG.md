# Журнал изменений — .anws v6

> Архитектурная эволюция v5 Discovery и незакрытого UX/security backlog v4.

## Формат записей

- **[ADD]** Новый утверждённый scope или документ.
- **[CHANGE]** Уточнение существующего решения.
- **[FIX]** Исправление противоречия документации.
- **[REMOVE]** Удаление устаревшего артефакта.

---

## 2026-08-06 — Единый источник вариантов CRM-полей

- **[CHANGE]** По подтверждению владельца `Варианты для полей` закреплены как единственное пользовательское место управления значениями select/radio/multi-select/checkbox-group полей; дублирующий inline-ввод в редакторе поля исключается.
- **[CHANGE]** `V6-505` дополнена lossless-преобразованием существующих inline-вариантов в именованные наборы и проверками публикации/отката без изменения сохранённых клиентских значений.

## 2026-08-03 — Инициализация

- **[ADD]** Создана версия `.anws/v6` через Copy & Evolve из v5.
- **[ADD]** В scope включены явно перечисленные владельцем разрывы configurable CRM, Students, Shared Tasks, Lesson links, Analytics, UX/UI и Production/Security.
- **[REMOVE]** Из рабочей версии исключены унаследованные v4 probe/task-review/challenge/release-артефакты; v4/v5 не изменялись.

## 2026-08-03 — PRD draft.1

- **[ADD]** Создан v6 PRD с 14 трассируемыми requirements для configurable CRM, Students, Shared Tasks, Lesson links, Analytics, UX/UI и Production/Security.
- **[CHANGE]** School defaults и sparse branch overrides закреплены как единая effective configuration model.
- **[CHANGE]** Config publication закреплена как draft → impact preview → atomic immutable revision.

## 2026-08-04 — Deep probe и PRD draft.2

- **[ADD]** Прочитан и сопоставлен 26-пунктный файл `ТЗ СРМ МагМуз-1 (1).docx` и четыре HolliHop-референса.
- **[ADD]** `00_PROBE_REPORT.md` фиксирует product claim-gap: workspace code не смонтирован, 327 navigation items остаются pending, desktop scrollbars не системны, client schedule/payment/deep-link workflows частичны.
- **[ADD]** PRD расширен requirements `REQ-WORKSPACE-001`, `REQ-DESKTOP-001`, `REQ-CLIENT-001`, `REQ-PAYMENT-001`, `REQ-NAV-002`, `REQ-UX-002`.
- **[CHANGE]** Completion теперь требует production route, real-account/device evidence и branch/school scope; isolated tests не считаются продуктовой приёмкой.
- **[CHANGE]** `.nexus-map` обновлена по текущим 1,119 source/test files и 365-дневной Git-истории.
- **[REMOVE]** Удалены скопированные, но ещё не переосмысленные v5 architecture/ADR/system-design файлы из v6; они будут созданы только после подтверждения PRD checkpoint.

## 2026-08-04 — PRD approved и UX/UI redesign

- **[CHANGE]** Владелец подтвердил PRD v6 полностью, включая 20 requirements и branch/school scope.
- **[ADD]** Запущено design-first проектирование полного adaptive UX/UI redesign поверх утверждённого визуального v7.
- **[ADD]** В PRD добавлены `REQ-SURFACE-001` и `REQ-NAV-003`: полноширинные/растягиваемые mobile surfaces, единый dirty-state Back contract и desktop context bar с breadcrumb hierarchy.

## 2026-08-04 — UX/UI architecture, challenge и blueprint

- **[ADD]** Созданы `02_ARCHITECTURE_OVERVIEW.md` и ADR-001..006: reuse-first v7, adaptive surfaces, unified navigation/history/breadcrumbs, desktop input, capability-projected role/scope UX и evidence gate.
- **[ADD]** Созданы L0/L1 App Experience Design с target anatomy, role/screen matrix, full-width mobile sheet, Android predictive Back, Windows scrollbars, client Lessons/Payments и unified dashboard/configuration UX.
- **[ADD]** Challenge review зафиксировал 12 рисков; Critical=0, High переведены в обязательные P0 constraints/tasks.
- **[ADD]** `05_TASKS.md`: 41 task + 8 INT gates, 312 engineering hours, 22/22 requirements traced.
- **[CHANGE]** v6 готов к owner design checkpoint; `/forge` до подтверждения дизайна не запускается.
