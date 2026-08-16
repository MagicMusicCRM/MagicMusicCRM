# Production hotfix версии абонемента `f030a583`

Дата: `2026-08-16` (МСК)

Результат: **PASS**

## Причина

- После клиентского исправления `1.5.15+195` preview отмены возвращал `201`,
  но commit возвращал `409 STALE_VERSION`.
- Production readback показал активный snapshot-backed абонемент с
  `subscriptions.version=1` и отсутствующей записью
  `commerce:issued-subscription` в `aggregate_versions`.
- Абонемент был создан старым путём после одноразовой migration `0091` и до
  исправления выдачи в release `1.5.14+194`. Поэтому прежний backfill его не
  видел, а общая v7 reconciliation этот класс drift не проверяла.

## Исправление

- Migration `0139_repair_issued_subscription_aggregate_versions` безопасно
  восстанавливает отсутствующие или отстающие aggregate versions для всех
  snapshot-backed абонементов и фиксирует исходное состояние в repair ledger.
- Down migration разрешена только пока восстановленная версия не была
  продвинута бизнес-командой; иначе rollback блокируется без потери истории.
- `v4-preflight` и штатная `v7-commerce-data` reconciliation теперь возвращают
  blocker `subscription_aggregate_version_mismatch` при повторном drift.
- Регрессионный PostgreSQL-тест удаляет aggregate у выданного абонемента,
  подтверждает blocker, применяет migration и завершает реальную cancel-команду.

## Проверки кандидата

- TDD RED: cancel завершался `ConflictException: Aggregate version is stale`.
- TDD GREEN: точечный контур `18/18` PASS.
- Полный backend suite: `186/186` suites, `1456/1456` tests.
- TypeScript typecheck и NestJS build: PASS.
- Migration `0139` local `up -> down -> up`: PASS.
- RepoWise change risk: `Elevated`, percentile `75.5`, review priority `high`.
- Semgrep: `74` правил по `3` TS-файлам, `0` findings.
- Gitleaks по commit `f030a583`: `0` leaks.
- Exact image: invalid production flags fail-closed, live/ready PASS,
  degraded readiness `503` PASS.
- Trivy exact image: `0` High/Critical vulnerabilities, `0` secrets,
  misconfigurations `0`.

## Образ и rollback

- Image: `magicmusiccrm-server:1.5.15-195-f030a583`.
- Image ID: `sha256:c0d272e74d020248a097a8592a96b62f54558c9ca76f8ea027a3235327322d86`.
- Labels: revision `f030a583475d571dd291bb788952c01402e9c761`, version
  `1.5.15+195`.
- Transport archive: `82 489 842` bytes, SHA-256
  `256D239E3BBAF527973E829CFCD5AA6E02AE4F270C7A43750EC9175AFDE5F3C1`.
- Previous image сохранён как
  `magicmusiccrm-server:rollback-pre-subscription-cancel-20260816T1720Z`.
- Rollback приложения использует прежний release override. Migration `0139`
  совместима с предыдущим server image и остаётся применённой; destructive down
  для production rollback не требуется.

## Backup и production gate

- Pre-deploy encrypted backup:
  `magicmusiccrm-staging-20260816T171534Z.tgz.enc`, `148 464` bytes,
  SHA-256
  `203B2E13942AB43913775E829C9EB7A004053A5DC23BCEBF4F4DD98FE38250B7`.
- Pre-deploy backup скопирован off-host и восстановлен в изолированный
  PostgreSQL: migration `0138`, subscriptions `1`, version drift `1`.
- Exact candidate применил к восстановленной копии migration `0139`: repairs
  `1`, drift `0`, reconciliation `issues=[]`.
- Post-deploy encrypted backup:
  `magicmusiccrm-staging-20260816T171913Z.tgz.enc`, `149 008` bytes,
  SHA-256
  `24FB9E4D760CDC27C7FF933B8FFC8DE3135B546AF500C6BCF55F161971F2B474`;
  off-host hash совпал.

## Production verification

- Runtime revision/version: `f030a583` / `1.5.15+195`; health `healthy`,
  restart count `0`.
- Migration head: `0139_repair_issued_subscription_aggregate_versions`.
- Repair ledger `1`, subscription aggregate drift `0`.
- Две независимые reconciliation: `issues=[]` / `issues=[]`.
- Platform outbox pending/dead-letter `0/0`.
- Свежие API fatal/unhandled и Caddy HTTP 5xx: `0/0`.
- Клиентские update manifests не менялись и продолжают указывать на
  `1.5.15+195`.

Production hotfix завершён. Сам абонемент не отменялся в ходе deploy: владелец
может безопасно повторить подтверждение в приложении.
