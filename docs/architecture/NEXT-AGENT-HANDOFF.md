# MagicMusicCRM — актуальная передача следующему агенту

> Зафиксировано: 2026-08-10
> Локальный кандидат: `1.5.1+180`
> Ветка: `codex/v7-production-readiness` от `main`/`origin/main`
> Статус: технический release candidate; production rollout и mega-UAT не завершены

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
   - `docs/audits/v7-production-readiness-180.md`.
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

- Flutter `666/666`;
- backend `158/158` suites, `1258/1258` tests;
- backend build PASS;
- production API healthy;
- локальный candidate `1.5.1+180`, тёмная тема; production не изменялся.
- server image `sha256:a07c39ff…`, revision `1559a45`: migration, fail-closed
  flags, live/ready, degraded HTTP 503 и Trivy image scan PASS.
- Inno Setup installer собран и install/launch/uninstall smoke PASS, но Windows
  Authenticode отсутствует; нужен доверенный certificate либо явное принятие
  unsigned distribution владельцем.

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
