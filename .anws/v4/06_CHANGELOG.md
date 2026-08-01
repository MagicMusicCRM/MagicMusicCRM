# Журнал изменений — .anws v4

> Этот файл фиксирует изменения архитектурной версии v4. Крупное расширение scope после утверждения v4 требует следующей версии архитектуры; точечные корректировки выполняются через `/change`.

## Формат записей

- **[ADD]** Добавление документа или решения.
- **[CHANGE]** Уточнение утверждённого требования.
- **[FIX]** Исправление ошибки документации.
- **[REMOVE]** Удаление устаревшего элемента из области истины v4.

---

## 2026-07-25 — Инициализация

- [ADD] Создана `.anws/v4` методом copy-and-evolve от v3.
- [ADD] Продуктовым источником назначена утверждённая спецификация `docs/PRE-V4-PRODUCT-SPEC.md`.
- [REMOVE] Старый `05_TASKS.md` исключён; новый чеклист будет создан через `/blueprint`.
- [CHANGE] Цель версии переключена с backend cutover на operational integrity, privacy, schedule lifecycle, subscriptions и connected workspace.

## 2026-07-25 — Genesis, System Design и Blueprint завершены

- [ADD] Утверждённая продуктовая спецификация перенесена в `01_PRD.md` без изменения 29 требований.
- [ADD] Создан `concept_model.json` с сущностями, потоками, связями и hard invariants.
- [ADD] Создан `02_ARCHITECTURE_OVERVIEW.md`: 8 логических систем внутри существующего Flutter/NestJS/PostgreSQL runtime.
- [ADD] Сохранены 6 runtime ADR v3 и приняты ADR-007…012 по capabilities/privacy, Lesson lifecycle, immutable finance, desktop workspace, idempotency/outbox и verification.
- [ADD] Созданы 8 детальных v4 system designs с operation contracts, data models, concurrency/failure/security/test/migration rules.
- [ADD] Проведён design challenge; 6 находок устранены, открытых Critical/High/Medium нет.
- [ADD] Создан `05_TASKS.md`: 66 атомарных L3-задач, 7 Sprint integration gates, 29/29 requirement coverage, 528 часов.
- [ADD] Проведён 6-pass task review; исправлена сумма roadmap, duplicate/unknown/cycle/coverage gaps отсутствуют.
- [REMOVE] Релизные evidence-отчёты v3 удалены из v4 scope и остаются в неизменной `.anws/v3`.
- [CHANGE] Следующий разрешённый шаг — выполнение S0 с T8.1.1; кодовые изменения v4 до старта `/forge` не выполнялись.
## 2026-07-29 — Уточнение teacher compensation

- [FIX] Владелец подтвердил доступные администратору способы оплаты преподавателя: фиксированная сумма за занятие (`fixed`), почасовая ставка (`hourly`) или без начисления (`none`).
- [CHANGE] `T5.1.1` и модель `TeacherCompensationFact` синхронизированы с `LessonSnapshot`; процентная оплата преподавателю исключена из текущего scope.
- [KEEP] Скидки абонементов остаются отдельным механизмом `percent/fixed`: процент рассчитывается от указанной базовой суммы.

## 2026-08-01 — Owner exception для security gate

- [CHANGE] Владелец разрешил пропустить history/security gate T8.4.1, чтобы продолжить technical/device/data/operations gates и staging rollout/rollback rehearsal.
- [KEEP] Исключение не считается прохождением security acceptance ADR-006: evidence маркируется `pass_with_owner_exception`, security=`owner_deferred`, `productionApproved=false`.
- [KEEP] Ротация ключей и получение GitHub admin-доступа остаются в backlog #16/#17; production rollout и INT-S6 до их устранения не разрешены.
