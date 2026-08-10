# MagicMusicCRM — актуальная передача следующему агенту

> Зафиксировано: 2026-08-10
> Кандидат: `1.5.1+179`
> Ветка: `main` → `origin/main`
> Статус: release candidate, production mega-UAT не завершён

## С чего начать

1. Прочитать `AGENTS.md`.
2. Проверить `git status --short --branch`, `git fetch origin` и совпадение
   `HEAD` с `origin/main`.
3. Прочитать `.anws/v7/05_TASKS.md`, особенно `T7.1.2` и `INT-S6`.
4. Открыть текущую UAT-матрицу и evidence index:
   - `docs/audits/v7-owner-production-mega-uat-result.md`;
   - `docs/audits/v7-owner-mega-uat-evidence/README.md`.
5. Продолжать только незакрытые строки матрицы. Новый глобальный аудит не нужен.

## Честный статус

Реализация v7 и финальный кандидат собраны, но полная пользовательская приёмка
ещё не доказана. На 2026-08-10 матрица содержит ровно 100 уникальных сценариев:

| Статус | Количество |
|---|---:|
| PASS | 7 |
| PARTIAL | 32 |
| PENDING | 61 |
| FAIL | 0 |
| BLOCKED | 0 |

`PARTIAL` не равен `PASS`. `INT-S6` остаётся открытым, пока каждая обязательная
строка не получит итоговый статус и предусмотренные UI/API/DB-доказательства.

Последний полный автоматический baseline:

- Flutter `664/664`;
- backend `157/157` suites, `1250/1250` tests;
- backend build PASS;
- production API healthy;
- candidate `1.5.1+179`, тёмная тема.

## Что уже является каноническим

- Одна пятиуровневая рабочая ролевая модель Client → Teacher → Admin → Manager
  → Director, плюс system_admin.
- Единая навигация с сохранением source tab и entity-text переходами.
- Одна Lead/Student карточка с desktop long canvas и compact mobile tabs.
- Одна task-модель; Teacher исключён из получателей staff-задач; Admin работает
  с branch-scoped доской и дефолтами `Мои задачи + Сегодня`.
- Один schedule/lesson transition flow без drag-and-drop обхода: причина,
  списание клиента, оплата преподавателя, preview и атомарный commit.
- Постоянные индивидуальные/групповые планы с обязательными teacher/room,
  конфликтами, историей и tray.
- Один append-only commerce path для личного счёта, трёх статусов оплаты,
  абонементов, рассрочки, чужого плательщика, сторно и возврата.
- Staff/Teacher создаются вместе с app user; старым сущностям доступ выдаётся
  отдельной атомарной командой; аудитории находятся внутри филиала.
- Светлая тема и legacy schedule-report UI не являются частью продукта.

## Последние production-подтверждения

- Вход/profile пяти реальных ролей подтверждён API `5/5`; секреты в evidence
  не сохранены.
- UAT-филиал, три аудитории, три Teacher app accounts, ставки и UAT
  Admin/Manager подтверждены API inventory.
- Lead workflow, merge/undo, webhook idempotency и связанная задача Admin
  прошли production-проверку.
- Admin закрыл задачу, созданную Director; история сохранила actor/time.
- Production API повторно проверен healthy после task fixes.

Точные файлы и скриншоты перечислены только в
`docs/audits/v7-owner-mega-uat-evidence/README.md`; не копировать один и тот же
кадр в разные сценарии без реального соответствия.

## Следующая работа

Продолжить `T7.1.2` по порядку из рабочей матрицы:

1. Закрывать `PENDING/PARTIAL` реальным Release UI для нужной роли и платформы.
2. Для Client и Teacher использовать Android emulator; для
   Admin/Manager/Director — Windows Release.
3. Проверять persisted результат через API/DB и reconciliation там, где это
   требуется планом.
4. При дефекте: воспроизведение → root-cause fix → релевантный regression →
   production retest → уникальное evidence.
5. Остановиться при финансовом drift, утечке прав, дубле эффекта или
   необъяснённом 5xx.

Финальное условие: `INT-S6` может быть закрыт только после независимой сверки
100 строк, hashes, defects/retests, итогового reconciliation и owner approval.

## Источники истины

1. Последние решения владельца.
2. `.anws/v7/01_PRD.md`, ADR и system design v7.
3. Текущая Release-сборка и production API/DB.
4. Production-reachable код в `main`.
5. Старые `.anws/v3`, `.anws/v4`, `.anws/v6`, прототипы и ранние аудиты —
   только историческое доказательство, не актуальная инструкция.

Удалённые из этого handoff сведения о ветке `codex/v5-configurable-crm`, HEAD
`532bf1e`, этапах 0–8 и ранних кандидатах были legacy-планом. Их нельзя
использовать для определения текущей готовности.

## Неподвижные правила

- Не объявлять готовность по наличию кода или теста без доступного UI-сценария.
- Не ослаблять backend RBAC/scope и не запускать скрытые forbidden requests.
- Не переписывать или физически удалять исторические платежи, ledger,
  settlement, audit и причины.
- Не создавать второй путь для оплат, задач, расписания, конфигурации или
  навигации.
- Не коммитить секреты, env, PII, production dumps и Office lock-файлы.
- Не закрывать открытые UAT-строки предположением.
