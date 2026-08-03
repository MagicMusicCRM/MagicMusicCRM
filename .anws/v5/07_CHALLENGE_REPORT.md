# MagicMusicCRM v4 — Design Challenge Report

**Дата:** 2026-07-25  
**Статус:** Passed after remediation  
**Scope:** `01_PRD.md`, `02_ARCHITECTURE_OVERVIEW.md`, ADR-001…012, все direct-файлы `04_SYSTEM_DESIGN/*.md`

## 1. Итог

Трёхмерный аудит завершён. Найдено 6 содержательных проблем; все исправлены в документах до создания технического плана. Открытых Critical/High/Medium нет.

| Измерение | Critical | High | Medium | Low | Исправлено |
|---|---:|---:|---:|---:|---:|
| System Design | 0 | 3 | 1 | 0 | 4 |
| Runtime Simulation | 0 | 0 | 1 | 0 | 1 |
| Engineering Implementation | 0 | 0 | 1 | 0 | 1 |
| **Итого** | **0** | **3** | **3** | **0** | **6** |

## 2. Логическая модель проверки

1. v4 меняет не deployment topology, а владельцев инвариантов внутри существующего modular monolith.
2. Наиболее опасные эффекты возникают на пересечении систем: роль→projection, lesson→money, subscription→reservation, tab→version.
3. Поэтому UI-скрытие, realtime и Redis не принимались за источник истины; проверялись PostgreSQL transaction и direct API denial.
4. Миграция считается частью дизайна, поскольку strict constraints на текущих данных могут остановить production workflow.
5. Наследованные v3 документы допустимы только если явно не расширяют и не переопределяют v4.

## 3. Pre-mortem: «релиз провалился через 6 месяцев»

| Цепочка провала | Контроль v4 |
|---|---|
| Старые роли остались в части endpoints → Teacher/Manager получил лишнее поле → выгрузка утекла | Capability registry, fail-closed projection, 6-role actor matrix и payload scans в [`access_control.md` §8–11](04_SYSTEM_DESIGN/access_control.md) |
| Future lessons содержат пропуски/пересечения → strict engine включён сразу → расписание массово перестало сохраняться | Data preflight, backfill, shadow validation и feature gate в [`schedule_lifecycle.md` §12](04_SYSTEM_DESIGN/schedule_lifecycle.md) |
| Worker повторил completion → два списания/начисления → статистика перестала сходиться | Unique lesson facts, durable claim, idempotency и одна transaction boundary в [`platform_integrity.md` §5–7](04_SYSTEM_DESIGN/platform_integrity.md) |
| Отмена абонемента совпала с завершением урока → subscription и reservation разошлись | Version/lock serialization и сохранённый LessonSnapshot в [`commerce.md` §8–10](04_SYSTEM_DESIGN/commerce.md) |
| Две вкладки молча перезаписали запись → потеря операторского ввода | Expected version, dirty conflict и no-last-write-wins в [`app_workspace.md` §6–7](04_SYSTEM_DESIGN/app_workspace.md) |
| Динамическая филиальная задача закрылась сотрудником без доказуемого доступа | Audience resolution audit в [`workflow_tasks.md` §4–8](04_SYSTEM_DESIGN/workflow_tasks.md) |

## 4. Найденные и устранённые проблемы

### DR-V4-001 — Наследованный v3 CRM противоречил v4 по ролям

- **Severity:** High
- **Dimension:** SD-1, SD-2
- **Место:** `04_SYSTEM_DESIGN/profile_crm.md` §5/§7 против `01_PRD.md` §6.
- **Доказательство:** v3 документ называл `admin` владельцем role management, а утверждённый PRD разрешает роли/permissions только Director/`system_admin`. Без явного precedence разработчик мог реализовать старую матрицу.
- **Исправление:** в начало наследованного документа добавлен supersession banner; [`README.md`](04_SYSTEM_DESIGN/README.md) объявляет новые v4 designs приоритетными.
- **Статус:** Resolved.

### DR-V4-002 — Access design не полностью выражал lifecycle root-ролей

- **Severity:** High
- **Dimension:** SD-4, EI-4
- **Место:** `01_PRD.md` §6.2 и REQ-RBAC-002 против ранней редакции `access_control.md` §2/§6.
- **Доказательство:** без правил reset overrides и защиты последнего `system_admin` смена роли сохраняла несовместимые права либо лишала систему аварийного входа.
- **Исправление:** добавлены атомарный reset overrides, emergency assignment любой роли и запрет деактивации/понижения последнего active root в [`access_control.md` §2, §6–7, §10](04_SYSTEM_DESIGN/access_control.md) и ADR-007.
- **Статус:** Resolved.

### DR-V4-003 — Архивирование клиента имело размытый actor scope

- **Severity:** High
- **Dimension:** SD-1, EI-4
- **Место:** REQ-CLIENT-002 и `client_crm.md` §5/§7.
- **Доказательство:** формулировка `permitted staff` не доказывала утверждённый запрет для Admin/Manager. UI мог скрыть кнопку, но API policy осталась бы неоднозначной.
- **Исправление:** preview и archive закреплены только за Director/`system_admin`, с direct 403 criteria в [`client_crm.md` §5](04_SYSTEM_DESIGN/client_crm.md).
- **Статус:** Resolved.

### DR-V4-004 — ADR ссылались на несуществующие REQ-id

- **Severity:** Medium
- **Dimension:** SD-1
- **Место:** ранние metadata ADR-007…011.
- **Доказательство:** диапазоны подразумевали REQ, которых нет в PRD, что ломало прямую/обратную трассировку.
- **Исправление:** ссылки заменены точными 29 approved REQ-id. Автопроверка: 29/29 referenced, 0 unknown.
- **Статус:** Resolved.

### DR-V4-005 — Некоторые runtime promises не имели порогов

- **Severity:** Medium
- **Dimension:** RS-2, RS-4
- **Место:** `schedule_lifecycle.md` §10, `reporting.md` §9, `app_workspace.md` §9.
- **Доказательство:** «автоматически», «большой export» и «синхронизация» без чисел нельзя превратить в alert/acceptance gate.
- **Исправление:** completion target ≤60 s/alert >120 s, cross-tab ≤2 s/access ≤5 s, export thresholds 10k/100k rows.
- **Статус:** Resolved.

### DR-V4-006 — Не хватало доказательства audience при динамической филиальной задаче

- **Severity:** Medium
- **Dimension:** EI-1, RS-3
- **Место:** `workflow_tasks.md` §4 и trade-off dynamic branch audience.
- **Доказательство:** membership вычисляется в момент закрытия; без зафиксированного matched selector позже невозможно доказать полномочие closer.
- **Исправление:** добавлен append-only `TaskAudienceResolutionAudit` с matched selector и membership version/time.
- **Статус:** Resolved.

## 5. Трёхмерный контроль после исправлений

### System Design

- **SD-1:** PRD, architecture, ADR и v4 designs согласованы; 29/29 REQ покрыты.
- **SD-2:** восемь владельцев данных/инвариантов отделены, deployment остаётся одним modular monolith.
- **SD-3:** write-зависимости направлены к PLATFORM; REPORTING read-only; SCHEDULE→COMMERCE пересекаются одной явной transaction boundary.
- **SD-4:** операции содержат actor/precondition/input/output/errors, а наследованные контракты имеют precedence banner.

### Runtime Simulation

- **RS-1:** create→reserve→complete, reschedule, replace/cancel и shared-close имеют terminal states.
- **RS-2:** realtime является invalidation после commit; dirty form не затирается.
- **RS-3:** expected versions, idempotency keys, unique facts и durable claims покрывают конкуренцию.
- **RS-4:** Redis/provider/realtime failure не теряет source data; backlog и poison work наблюдаемы.

### Engineering Implementation

- **EI-1:** state machines, policy evaluator и constraints unit-testable; transaction/concurrency проверяются с реальным PostgreSQL.
- **EI-2:** capability registry, EntityLink и platform transaction runner уменьшают число разрозненных проверок.
- **EI-3:** client card/report queries требуют batched read models; export имеет limits.
- **EI-4:** server-side policies, actor-scoped queries, safe DTO и redacted events определены.

## 6. Gate

Архитектурный дизайн допускается к `/blueprint`. Обязательные условия будущего исполнения:

- сначала восстановить чистый локальный server integration baseline;
- strict schedule/capability switch не включать до shadow comparison и data preflight;
- ни один Sprint не закрывать без actor/concurrency/reconciliation evidence;
- новые Critical/High findings блокируют начало соответствующей implementation wave.
