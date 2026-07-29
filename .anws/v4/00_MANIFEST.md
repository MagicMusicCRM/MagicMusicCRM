# .anws v4 — Operational Integrity & Connected Workspace

**Дата создания**: 2026-07-25  
**Статус**: Planning complete — Ready for execution  
**Предыдущая версия**: v3 (Backend Independence)  
**Утверждённый продуктовый источник**: `docs/PRE-V4-PRODUCT-SPEC.md`

## Цели версии

Привести MagicMusicCRM к единой и проверяемой бизнес-логике ролей, занятий, расписания, абонементов, задач и связанной навигации, сохранив собственный NestJS/PostgreSQL runtime v3 и историческую финансовую целостность.

## Основные изменения

- Пакеты ролей и персональные разрешения с Директором как старшей бизнес-ролью.
- Безусловный, но скрытый от бизнес-интерфейса аварийный `system_admin`.
- Удаление ручной посещаемости и автоматический идемпотентный lifecycle занятия.
- Строгая валидация расписания, рабочих часов, филиалов и конфликтов.
- Снимки коммерческих условий, замена и отмена выданных абонементов без переписывания платежей.
- Связанный граф переходов и account-scoped workspace до 10 вкладок на ПК.
- Общие неблокирующие задачи и корректные Excel-выгрузки.

## Список документов

- [x] `00_MANIFEST.md`
- [x] `concept_model.json`
- [x] `01_PRD.md`
- [x] `02_ARCHITECTURE_OVERVIEW.md`
- [x] `03_ADR/` (6 inherited + 6 v4 ADR)
- [x] `04_SYSTEM_DESIGN/` (8 v4 systems + inherited v3 runtime designs)
- [x] `05_TASKS.md` (66 L3 + 7 INT, 528 ч)
- [x] `05_TASKS_REVIEW.md`
- [x] `06_CHANGELOG.md`
- [x] `07_CHALLENGE_REPORT.md`

## Границы версии

- v4 эволюционирует текущий Flutter/NestJS/PostgreSQL продукт; это не rewrite.
- Документы v3 остаются неизменной историей backend-independence.
- Release evidence и acceptance-отчёты v3 не копируются в область истины v4.
- Кодирование начинается только по чеклисту `.anws/v4/05_TASKS.md`.
