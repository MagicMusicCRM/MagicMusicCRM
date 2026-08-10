# MagicMusicCRM 1.5.1+180 — production read-only preflight

- Дата: `2026-08-10T19:05Z`
- Target: `api.magicmusiccrm.ru`
- Режим: read-only SSH/HTTP/Docker inspection
- Production mutations: `0`

## Результат

| Проверка | Результат |
|---|---|
| SSH deploy boundary | PASS |
| Compose services | `api,caddy,postgres,redis`, все running |
| API Docker health | `healthy` |
| Internal `/api/health/live` | `status=ok` |
| Internal `/api/health/ready` | все checks `ok` |
| Public `/api/health/live` | `status=ok` |
| Public `/api/health/ready` | все checks `ok` |
| Access/Schedule rollout | configured/effective `v4`, kill switches false |
| Completion worker | due/retry/poison `0`, oldest due отсутствует |
| Platform outbox | pending/dead-letter `0`, oldest due отсутствует |
| Current migration | `0115_school_task_staff_recipients` |
| Current API image | `sha256:85578696878d…` |
| Encrypted backup inventory | `1`, latest SHA-256 PASS |
| `/opt/magicmusiccrm` disk | 33% used, 33,380,176 KiB available |

API container намеренно не публикует порт `3000` на host network: internal
health проверен через `docker compose exec api`, public health — через Caddy.
Это ожидаемая network boundary, не outage.

## Готовность к maintenance window

Preflight не выявил runtime, worker, outbox, disk или backup blocker. Production
находится на schema `0115`; кандидат содержит additive migrations `0116..0118`.

До deployment остаётся обязательная отдельная команда владельца на production
backup/rollout. После неё последовательность фиксирована:

1. подтвердить outbox/worker zero и приостановить completion worker;
2. создать новый encrypted backup, проверить SHA и скопировать off-host;
3. сохранить current image ID `855786…` как immutable rollback target;
4. загрузить image `a07c39…`, выполнить migrations `0116..0118` и заменить API;
5. проверить live/ready, `latestMigrationId=0118`, v4 effective paths и роли;
6. выполнить v7 reconciliation, возобновить worker и наблюдать метрики;
7. при любом stop-condition вернуть image `855786…` без destructive schema down.

Секреты, env, backup paths и production PII в evidence не сохранены.
