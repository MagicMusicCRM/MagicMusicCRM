# MagicMusicCRM v7 — Challenge Report

**Дата:** 2026-08-07  
**Режим:** DESIGN  
**Вердикт:** 🟢 проектирование допускается к `/blueprint`; открытых
Critical/High после исправлений нет.

## 1. Сводка

| Измерение | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| System Design | 1 исправлен | 1 исправлен | 0 | 0 |
| Runtime Simulation | 0 | 1 исправлен | 0 | 0 |
| Engineering | 0 | 0 | 1 принят в gate | 0 |
| **Открыто** | **0** | **0** | **1** | **0** |

## 2. Методология

Проверены PRD, Architecture Overview, ADR-001..010 и все L0/L1 design files.
Проведены pre-mortem транзакций purchase→installment→cancel, payment→reverse,
lesson→move/settle и config publish под различными ролями. Локальный `sthink`
CLI отсутствовал, поэтому использован ограниченный ручной пошаговый разбор с
проверкой каждого вывода по текущей схеме/services и официальной документации
PostgreSQL/Flutter из research report.

## 3. Pre-Mortem

Сценарий провала через шесть месяцев: один клиент купил абонемент со счёта
родственника, часть рассрочки подтверждена, занятие перенесли из календаря, а
абонемент отменили. Баланс и отчёт разошлись, причина недоступна другой смене.

Наиболее вероятная цепочка: неверное определение funded amount → неполный credit
при cancel → старый direct lesson PATCH обходит settlement → mixed configuration
publish позволяет Manager поменять protected catalog → разные report queries
по-разному исключают reversal. Найденные ниже места соответствовали этой цепочке.

## 4. Findings

### CH-V7-01 — One-time wallet purchase получал нулевой refund cap

- **Severity:** Critical — исправлен до планирования.
- **Адрес:** `01_PRD.md` US-V7-003; `commerce_integrity.detail.md` §5.
- **Доказательство:** one-time purchase использует ранее подтверждённые деньги
  wallet и не обязана иметь новый `app.payments` с `issued_subscription_id`.
  Формула только по linked paid rows вернула бы 0 при полностью оплаченной
  покупке. Cancel оставил бы списание без возврата.
- **Исправление:** введён `confirmedFundedMinor`: one-time = вся атомарно
  списанная стоимость; installment = подтверждённые части. Cancel отдельно
  закрывает unfunded obligation и возвращает funded unused share, одним итоговым
  credit без double count.
- **Проверка:** PostgreSQL cases one-time existing wallet, 0/partial/full used;
  installment 1/N paid; lower refund reason; reconciliation delta 0.

### CH-V7-02 — Mixed config snapshot обходил Director-only catalog право

- **Severity:** High — исправлен.
- **Адрес:** `commerce_integrity.detail.md` §1 Catalog additions;
  `access_audit_v7.md` §3.
- **Доказательство:** текущий `CrmConfigurationService` публикует один JSON
  snapshot, а Manager уже может менять разрешённые branch CRM settings. Одно
  скрытие UI не мешало отправить изменённые commerce arrays вместе с легальной
  правкой.
- **Исправление:** publish сравнивает protected catalog segments с effective
  snapshot; без `config.commerce.manage` они обязаны быть byte-equivalent.
- **Проверка:** Manager legitimate CRM publish succeeds, same request with one
  changed settlement/pay key = 403/422 and writes 0 revision/audit/outbox.

### CH-V7-03 — Existing auto completion мог начислить teacher pay без выбора

- **Severity:** High — исправлен.
- **Адрес:** `schedule_v7.md` §8; `schedule_v7.detail.md` §1.
- **Доказательство:** текущий completion worker переводит lessons terminal и
  settlement boundary создаёт/связывает facts. PRD требует, чтобы сотрудник
  всегда явно выбирал teacher compensation. Оставленный worker обошёл бы это.
- **Исправление:** worker создаёт только `settlement_pending`; financial terminal
  facts создаёт explicit settle command. Legacy series compensation становится
  display-only, не default выбора.
- **Проверка:** clock test даёт pending и 0 finance facts; staff settle создаёт N
  client facts + 1 teacher accrual exactly once.

### CH-V7-04 — Ordinary report exclusion может остаться неодинаковым

- **Severity:** Medium — открыт как обязательный implementation gate.
- **Адрес:** `commerce_integrity.detail.md` §8; текущие
  `commerce-projection.repository.ts`, `finance.service.ts`, dashboard/report SQL.
- **Доказательство:** код содержит несколько независимых запросов к
  `app.payments/account_adjustments`; добавление exclusion только в Client Card
  оставит school reports/export со старой суммой.
- **Последствие:** UI balance верен, отчёт/экспорт неверен.
- **Решение:** до coding wave сгенерировать inventory всех ordinary finance SQL,
  подключить общий view/predicate и оставить contract test `unowned=0`.
- **Проверка:** одна reversal fixture отсутствует во всех ordinary
  card/dashboard/report/export totals и присутствует в technical history.

## 5. Проверенные гипотезы

| Гипотеза | Результат |
|---|---|
| Existing facts можно расширить без второго ledger | подтверждено migrations 0089/0100 и current projections |
| Row locks достаточны вместо global Serializable | подтверждено при fixed key order + version/idempotency tests |
| Group plan может иметь один subscription id | опровергнуто; нужен participant→subscription mapping |
| Цвет достаточен для settlement state | опровергнуто PRD/accessibility; label/icon обязателен |
| Admin client finance требует school finance | опровергнуто existing capability boundary; keys разделены |

## 6. Обязательный план действий

### P0

- migration + backfill payer/payment/exclusion/config/plan/note;
- atomic purchase/payment/cancel/reversal and settlement transitions;
- protected config publish and Actor Matrix;
- finance SQL inventory/common exclusion;
- concurrency/fault/reconciliation tests.

### P1

- recurring plan/tray UI, shared note/history and Client Card actions;
- adaptive Schedule/Commerce forms and all mutation callsite migration.

### P2

- indexes/query tuning только после bounded p95/EXPLAIN evidence.

## 7. Final verdict

🟢 **GREEN FOR BLUEPRINT.** Design internally consistent after corrections.
Coding is forbidden to declare complete until CH-V7-04 inventory shows every
ordinary finance consumer owned and reconciliation/role/device gates pass.

