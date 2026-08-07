# MagicMusicCRM v7 — Task Review

**Дата:** 2026-08-07  
**Вердикт:** PASS — открытых Critical/High нет; план допускается к `/forge`.

## 1. Сводка шести passes

| Pass | Проверка | Critical | High | Medium | Результат |
|---|---|---:|---:|---:|---|
| A | дубликаты/пересекающиеся outputs | 0 | 0 | 0 | один владелец на command/UI/schema |
| B | неопределённости/TODO | 0 | 0 | 0 | заглушек и «слов-ощущений» нет |
| C | детализация/поля/verification | 0 | 0 | 0 | 30/30 задач имеют обязательные поля |
| D | термины/зависимости/сироты | 0 | 0 | 0 | IDs и systems согласованы |
| E | прямое/обратное US/REQ покрытие | 0 | 0 | 0 | 11/11 REQ, 11/11 stories |
| F | размер/критический путь | 0 | 0 | 1 | длинный путь принят, разбит INT gates |

До финального PASS исправлены две перегруженные задачи: schema разделена на
commerce и schedule/config/note, а transition — на atomic command и отдельный
worker/bypass/bulk gate. Все Level-3 оценки теперь 4–8 часов (INT: 3–4).

## 2. Coverage matrix

| Requirement | Основные задачи | Статус |
|---|---|---|
| REQ-COMMERCE-101 | T1.1.2, T2.1.1, T5.1.1 | Полное |
| REQ-COMMERCE-102 | T2.1.4, T5.1.1 | Полное |
| REQ-PAYMENT-101 | T1.1.2, T2.1.2, T5.1.1 | Полное |
| REQ-PAYMENT-102 | T1.1.1, T1.1.2, T2.1.3, T5.1.1 | Полное |
| REQ-LESSON-101 | T1.1.3, T3.1.1, T3.1.2, T5.1.4 | Полное |
| REQ-LESSON-102 | T3.1.1, T3.1.2, T5.1.4 | Полное |
| REQ-SCHEDULE-101 | T3.1.3, T3.1.4, T3.1.5 | Полное |
| REQ-SCHEDULE-102 | T1.1.3, T4.1.1, T4.1.2, T4.1.3 | Полное |
| REQ-CLIENT-101 | T5.1.3, T6.1.2 | Полное |
| REQ-CLIENT-102 | T1.1.3, T2.1.5, T5.1.2 | Полное |
| REQ-REPORT-101 | T1.1.1, T1.1.4, T2.1.3, T2.1.5, T6.1.1 | Полное |

Обратное покрытие: каждая из 24 implementation tasks содержит REQ; шесть INT
milestones обоснованы release strategy ADR-007/PRD DoD.

## 3. Critical path

```mermaid
flowchart LR
  S0["Schema + backfill"] --> S1["Purchase/payment/access"]
  S1 --> S2["Catalog + settlement + transition"]
  S2 --> S3["Recurring plans"]
  S3 --> S4["Integrated Client Card"]
  S4 --> S5["Full/device/release gates"]
```

**Medium TR-V7-01:** путь последователен из-за реальных data/API/UI
зависимостей. Параллелить schema/commands без общей source of truth опаснее.
Риск ограничен шестью INT gates; S4 note/history и Commerce UI могут начинаться
после своих S0/S1 prerequisites параллельно S2/S3.

## 4. Interface traceability

- Schema outputs T1.1.2/3 → backfill T1.1.4 → command repositories S1/S2/S3.
- S1 APIs/projections → Flutter commerce T5.1.1.
- S2 transition API → one Flutter decision controller T3.1.5.
- S3 plan/tray API → Client Card plan section T4.1.3.
- Access/audit T2.1.5 → note/history and all UI guards.
- Inventory T1.1.1 remains a stale-check through S1/S2/S5.

## 5. Verification balance

- Pure formulas: unit tests.
- Money/time/concurrency: PostgreSQL integration.
- Route/payload permissions: Actor Matrix/contracts.
- Widgets/adaptive behavior: targeted Flutter tests.
- Smoke/E2E: only INT milestones and final devices.
- Full regressions: T6.1.1, not repeated after every small task.

## 6. Итог

План минимально достаточен, traceable и проверяем. Добавлять отдельные задачи на
микросервис, cache, analytics read-store или automated teacher-pay rules нельзя:
они не поддержаны PRD и нарушат YAGNI/ADR.

