# .anws v6 — Configurable CRM & Product UX Completion

**Дата создания**: 2026-08-03  
**Статус**: UX/UI Blueprint ready — ожидает owner design checkpoint  
**Предыдущая версия**: v5 (незавершённый Discovery)

## Цели версии

Завершить управляемую конфигурацию CRM и закрыть подтверждённые владельцем продуктовые разрывы в desktop workspace, mouse UX, карточке клиента, расписании, оплатах, учениках, общих задачах, связанных переходах, аналитике и production/security-приёмке.

## Основные изменения

- Единая конфигурационная модель поверх существующих custom fields, capability overrides и каталога абонементов.
- Настраиваемая директором воронка учеников и основной сценарий создания ученика.
- Один канонический UX общих задач без дублирующих действий и legacy-сценария.
- Типизированные переходы из карточки занятия к ученику, преподавателю и аудитории.
- Единый dashboard аналитики с общими фильтрами при сохранении финансовых RBAC-границ.
- Сквозной UX/UI-аудит и обязательный production/security gate без отложенной High-находки.
- Реально подключённые account-scoped Windows tabs с restart restore и logout clear.
- Видимые draggable scrollbars для всех применимых desktop scroll axes.
- Полноразмерная карточка клиента с canonical Lessons/preferred calendar и полным Payments workflow.
- Adaptive mobile surfaces: primary routes, полноширинные expandable sheets и единый UI/system/predictive Back.
- Desktop context bar: per-tab Back/Forward, typed breadcrumbs, page actions и системные deep links.
- Role-oriented, capability-projected UX для Client/Teacher/Admin/Manager/Director с явным school/branch scope.

## Список документов

- [x] `00_MANIFEST.md`
- [x] `00_PROBE_REPORT.md`
- [x] `concept_model.json`
- [x] `01_PRD.md`
- [x] `02_ARCHITECTURE_OVERVIEW.md`
- [x] `03_ADR/` (ADR-001..006)
- [x] `04_SYSTEM_DESIGN/` (L0 + detailed UX contract + research)
- [x] `05_TASKS.md` (41 tasks + 8 integration gates)
- [x] `06_CHANGELOG.md`
- [x] `07_CHALLENGE_REPORT.md`

## Границы версии

- Существующие v4 domain-инварианты, API-контракты, финансовые факты и capability-модель остаются источником истины.
- `implemented` означает production-mounted и принятое на real account поведение; isolated class/test без маршрута не считается выполнением.
- Конфигурация расширяет существующие реестры; параллельный generic platform и новый UI framework не создаются.
- Production-разрешение возможно только после Critical/High=0, закрытого security gate и явного owner UAT.
