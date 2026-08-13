# Production backend error hardening `23688482`

Дата: `2026-08-14` (МСК)

Результат: **PASS**

## Что исправлено

- `jobId`, `entityId` и `userId` валидируются до SQL; некорректный UUID теперь
  даёт клиентскую ошибку, а не PostgreSQL `500`.
- Readiness изолирует сбой БД/worker probe и возвращает структурированный
  degraded `503`, сохраняя диагностику остальных проверок.
- Async report export получил durable drain queued/stale jobs, атомарный claim,
  обработку rejected promise и гарантированную запись terminal failure.
- Обязательный login OTP считается созданным только после фактической отправки.
  При недоступности обоих email providers challenge закрывается, retry
  исчерпывается и API возвращает понятный `503 OTP_DELIVERY_UNAVAILABLE` вместо
  повторяющегося OTP-loop.
- Notification и analytics timers больше не скрывают rejected promise.
- Production compose больше не запускает API как staging; обязательные
  completion/outbox/installment/reminder/series workers проверяются fail-closed.
- Включены JSON access logs Caddy, ротация Docker logs и минутный monitor
  readiness/5xx/backend errors/poison queues/stale exports.

## Release gates

- Runtime revision: `23688482fe1294e66ebabf3f4a275c401f49756f`.
- Backend: `182/182` suites, `1439/1439` tests; typecheck/build PASS.
- Strict security gate: `11 PASS / 0 WARN / 0 FAIL`; npm audit `0`.
- Semgrep: `74` rules, `577` targets, `0` findings.
- Gitleaks: `0` leaks in both commits.
- Trivy exact image: `0` High/Critical vulnerabilities, `0` secrets.
- Exact image: invalid production flags fail-closed; healthy readiness and
  degraded database `503` PASS.
- RepoWise change risk: elevated, `87.3` percentile; весь backend suite и
  отдельные env/monitoring contracts были обязательными из-за ширины diff.

## Backup и rollback

- Новый encrypted backup:
  `magicmusiccrm-staging-20260813T221654Z.tgz.enc`, `118640` bytes,
  SHA-256
  `fa0b33aafd6e7a6928a5b7f53286cfc1ad95cae752680c488b06b3d306f92e6b`.
- Off-host копия сохранена в `Documents/MagicMusicCRM Backups`; SHA-256 совпал.
- Архив расшифрован, внутренние SHA-256 проверены, `pg_restore -l` PASS.
- Старый image сохранён как
  `magicmusiccrm-server:rollback-pre-backend-errors-20260813T222422Z`.
- Первый cutover дошёл до readiness/runtime/reconciliation, но deploy-only SQL
  использовал неверное имя `app.platform_outbox`. Automatic rollback вернул
  `2d1c6255`, readiness и restart `0`. После исправления проверки повторный
  идемпотентный cutover завершился PASS; данные и migration ledger не менялись.

## Production rollout

- Image: `magicmusiccrm-server:1.5.7-187-23688482`.
- Image ID:
  `sha256:5b2f5c3bf708552a12b4a93b2e26e8375694b8dcbdb6d1f21f8f48fe19aa4f4a`.
- Transport archive: `82770432` bytes, SHA-256
  `56b5d67465d3f0b75c77b3169ab513e207efdff0b98784b93ecbba962f2b2d7b`.
- Runtime: `NODE_ENV=production`; семь обязательных worker/reminder flags
  равны `true`; API health `healthy`, restart count `0`.
- Migration осталась `0135_requeue_organization_outbox`.
- Reconciliation `issues=[]`; queues
  `pending outbox / dead outbox / exports / poison tasks / poison installments`
  равны `0|0|0|0|0`.
- Initial и delayed public readiness PASS; свежие API error lines `0`, Caddy
  `5xx=0`, JSON access logging PASS.
- Monitor установлен одной идемпотентной cron-записью; самостоятельный прогон,
  forced alert и recovery drill PASS.

Sentry DSN и внешний Telegram sink на сервере не заданы. Это не влияет на
локальное обнаружение: cron, rotated container logs, persistent alert log и
backend error log работают. Для внешней доставки нужен отдельный credential,
который нельзя сгенерировать из репозитория.

Клиентские manifests и артефакты не менялись: установленный клиент
`1.5.7+187` использует обновлённый production API.
