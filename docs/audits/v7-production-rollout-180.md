# MagicMusicCRM 1.5.1+180 — production rollout

- Дата: `2026-08-10`
- Target: `https://api.magicmusiccrm.ru`
- Owner authorization: production backup + rollout с автоматическим rollback
- Windows distribution: unsigned, риск явно принят владельцем
- Итог rollout: **PASS**

## Развёрнутый кандидат

| Контроль | Результат |
|---|---|
| Server image | `sha256:a07c39ffe05acf5743ae1a103a1358b2ad24305ef193b2e5579b4923baf9292f` |
| OCI revision | `1559a45461afcd8e692b5f0e047ba2a707e40987` |
| Runtime user | `magiccrm` (non-root) |
| Image transport SHA-256 | `1F775A4D89D66E2F9309A65C85A09EAFB183AF1402CB9672F23BF65CEE2AECC4` |
| Production Compose SHA-256 | `4FB1FDCBC94680CA9F06387CDFADBB8CF5ECAFD6A81CB66BAC2C853F51FC8044` |
| Migration ledger | `0115` → `0118_lesson_participant_exclusions` |
| Healthcheck | `/api/health/ready`, fail-closed |
| Completion worker | paused при cutover, затем штатно возобновлён |

Образ доставлен как неизменяемый Docker tar. Из-за ограничения скорости одного
SSH-потока transport был разбит на десять quarantine-частей; собранный файл
допущен к `docker load` только после полного совпадения SHA-256. Загруженный
image ID, revision, non-root user и readiness healthcheck совпали с локальным
release ledger.

## Backup и restore-check

Непосредственно перед rollout создан новый AES-256-CBC/PBKDF2 encrypted backup:

- размер `33,514,704` bytes;
- SHA-256 `2912160E9631EF3FE40792BC0C7CFA2B39FB21D411912CFC6B3349FD837FA90B`;
- remote checksum и off-host checksum совпали;
- пробное расшифрование, tar structure и внутренний `SHA256SUMS` — PASS;
- `pg_restore --list` — PASS;
- isolated restore состояния `0115` — PASS;
- агрегаты users/profiles/branches/lessons/subscriptions/payments совпали с
  исходным snapshot;
- migrations `0116..0118` на восстановленной БД — PASS;
- v7 reconciliation восстановленной БД — `0 issues`;
- временная БД и plaintext-каталог после проверки удалены, production DB не
  была целью restore.

Первый запуск backup выявил дефект legacy-скрипта: Docker dotenv исполнялся как
Bash и падал на корректном значении с пробелами. Канонический скрипт исправлен:
dotenv теперь разбирает Docker Compose, а database identity читается внутри
PostgreSQL-контейнера. `bash -n`, live compose-env probe, реальный backup и
restore-check прошли; прежняя версия скрипта сохранена как rollback copy.

## Cutover и автоматический rollback

Перед переключением повторно подтверждены старый image ID, schema `0115`,
worker/outbox zero и v4/v4. Compose и `.env` получили закрытые rollback-копии.
Worker был временно отключён, новый image назначен существующему каноническому
service tag, пересоздан только `api`.

Stop-conditions включали ошибку migration/startup, неверный image ID,
unhealthy container, internal/public readiness, не-`0118` ledger, v4 drift,
worker poison/retry и outbox dead-letter. Ни один stop-condition не возник,
автоматический rollback не запускался.

Rollback target сохранён неизменяемым тегом и указывает на прежний image
`sha256:85578696878dc7e04a34b41066bf70f7f9e4ee00b0b593939a9570338d62be3a`.
Additive schema не откатывается разрушительным `down`; старый migration runner
и readiness допускают дополнительные ledger rows.

## Post-deploy verification

| Проверка | Результат |
|---|---|
| Internal live/ready | PASS |
| Public live/ready | PASS |
| v4 access/schedule | configured/effective `v4`, kill switches `false` |
| Five-role login + private JWT | `5/5` (`client/teacher/admin/manager/director`) |
| V7 reconciliation | два запуска, оба `0 issues` |
| Worker | active; due/retry/poison `0/0/0` |
| Platform outbox | pending/dead-letter `0/0` |
| Migration objects | views/constraint/exclusion table/immutable trigger PASS |
| PostgreSQL integrity | not-valid constraints `0`, invalid indexes `0` |
| API restart count | `0` после финального запуска |
| API error markers | `0` |
| Caddy 5xx после финального запуска | `0` |
| Public readiness latency | 5 samples, average `0.031s`, max `0.033874s` |

Зафиксированные aggregate counts после rollout: users `1096`, profiles `1096`,
branches `3`, lessons `33845`, subscriptions `4`, ordinary payments `3252`.
Секреты, токены, env, backup paths и production PII в evidence не сохранены.

## Решение

Production rollout `1.5.1+180` технически завершён и остаётся healthy.
Это закрывает инфраструктурную часть G0 и runtime-часть UAT-135, но не заменяет
оставшиеся production UI/API/DB-сценарии owner mega-UAT. `T7.1.2` и `INT-S6`
остаются открыты до финализации всей 100-строчной матрицы и owner approval.
