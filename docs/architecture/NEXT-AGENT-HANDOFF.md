# MagicMusicCRM — актуальная передача следующему агенту

> Зафиксировано: 2026-08-11
> Production: `1.5.1+181` (Teacher compensation refinement), exact image `sha256:5fbd5a29…`
> Ветка: `codex/v7-production-readiness` от `main`/`origin/main`
> Статус: production rollout PASS; owner mega-UAT не завершён

## С чего начать

1. Прочитать `AGENTS.md`.
2. Проверить `git status --short --branch`, `git fetch origin` и совпадение
   `HEAD` с `origin/main`.
3. Прочитать `.nexus-map/INDEX.md`, затем запрашивать только нужные строки
   исчерпывающих JSON из `.nexus-map/inventory/`.
4. В `.anws/v7/05_TASKS.md` открыть только определения `T7.1.2` и `INT-S6`.
5. Открыть текущую UAT-матрицу и evidence index:
   - `docs/audits/v7-owner-production-mega-uat-result.md`;
   - `docs/audits/v7-owner-mega-uat-evidence/README.md`;
   - `docs/audits/v7-production-readiness-180.md`;
   - `docs/audits/v7-teacher-compensation-181.md`;
   - `docs/audits/v7-production-rollout-181.md`.
6. Продолжать только незакрытые строки матрицы. Новый глобальный аудит не нужен.

## Честный статус

Реализация v7 и финальный кандидат собраны, но полная пользовательская приёмка
ещё не доказана. На 2026-08-11 матрица содержит ровно 100 уникальных сценариев:

| Статус | Количество |
|---|---:|
| PASS | 10 |
| PARTIAL | 29 |
| PENDING | 61 |
| FAIL | 0 |
| BLOCKED | 0 |

`PARTIAL` не равен `PASS`. `INT-S6` остаётся открытым, пока каждая обязательная
строка не получит итоговый статус и предусмотренные UI/API/DB-доказательства.

Последний полный автоматический baseline:

- Flutter `667/667`;
- backend `158/158` suites, `1258/1258` tests;
- backend build PASS;
- production `+181` exact image `sha256:5fbd5a29…`, revision `17ce254`:
  migration/fail-closed/live/ready/degraded-503 и Trivy `0/0` PASS;
- Windows ZIP `+181` launch PASS, APK/AAB build+signature PASS; Android 15/API
  35 install/launch build `181` PASS без FATAL/ANR/E/flutter;
- production API и оба update-манифеста работают на `1.5.1+181`, migration
  `0118`; worker active, worker/outbox/reconcile drift `0`;
- Inno Setup `+181` собран, но его интерактивный elevated install smoke из
  non-interactive сессии не выполнен; portable ZIP launch PASS. Windows
  Authenticode отсутствует, и владелец 2026-08-10 явно принял unsigned
  distribution.

Production rollout 2026-08-10 прошёл с новым encrypted backup, совпавшей
off-host SHA, isolated restore `0115`, candidate migration `0118`, двумя
нулевыми reconciliation, five-role JWT smoke и автоматическим rollback gate.
Подробности без секретов/PII: `docs/audits/v7-production-rollout-180.md`.

Production rollout `1.5.1+181` 2026-08-11 также прошёл с новым encrypted
off-host backup, isolated restore, worker pause/resume и автоматическим
rollback gate. Серверный и клиентский каналы переключены на build `181`, обе
reconciliation пусты, five-role smoke `5/5`, restart/runtime error/Caddy 5xx —
`0`. Подробности: `docs/audits/v7-production-rollout-181.md`.

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

## Неподвижные правила

- Не объявлять готовность по наличию кода или теста без доступного UI-сценария.
- Не коммитить секреты, env, PII, production dumps и Office lock-файлы.
- Не закрывать открытые UAT-строки предположением.
