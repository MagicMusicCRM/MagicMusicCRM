# Production rollout `1.5.18+198`

Дата: `2026-08-28` (МСК)

Результат: **PASS**

## Зафиксированный кандидат

- Release commit: `744959efcef31394895a59a7e782d015364caf29`.
- Tag и GitHub Release: `v1.5.18`.
- Server image: `magicmusiccrm-server:1.5.18-198-744959ef`.
- Image ID: `sha256:5bd6ee44919c5f4f700771c34c33d514d288cead2023fdf329597a9af32b820f`.
- Image labels: revision `744959efcef31394895a59a7e782d015364caf29`,
  version `1.5.18+198`; runtime user `magiccrm`.
- Migration head: `0141_repair_legacy_subscription_aggregate_versions`.

## Изменение

- Рабочие разделы надёжнее сохраняют состояние при загрузке и обновлении
  данных.
- Усилены проверки доступа и согласованности операций расписания, финансов и
  задач.
- Исправлены устаревшие предварительные расчёты и отдельные ошибки форм и
  отчётов.
- Обновлена внутренняя архитектура приложения и сервера без изменения
  пользовательской истории.
- Миграция `0141` идемпотентно добавляет отсутствующую aggregate version для
  ранее восстановленной legacy-выдачи абонемента; исторические факты не
  удаляются и не переписываются.

## Release gates

- Backend: `259/259` suites, `3186/3186` tests; typecheck и NestJS build PASS.
- Flutter: `1355/1355` tests, targeted `39/39`; `flutter analyze` без замечаний.
- Production-like gate: migration `0141`, reconciliation `0`, invalid config
  fail-closed, live/ready PASS.
- Exact image gate: production flags, healthy readiness и ожидаемая degraded
  readiness `503` PASS.
- Trivy финального image: `0` High/Critical vulnerabilities, `0` secrets.
  Первоначальный image был отклонён из-за `CVE-2026-14456`; runtime-пакеты
  `libcrypto3` и `libssl3` обновлены с `3.5.7-r0` до `3.5.8-r0`.
- Codex Security exact diff: `646/646` review items, `0` подтверждённых
  findings. Девять Semgrep и две Gitleaks-находки получили статическую
  source-to-sink валидацию и не подтвердились как уязвимости или реальные
  секреты.
- Windows portable: embedded version `1.5.18+198`, launch PASS; ZIP содержит
  `39` безопасных entries. Setup ProductVersion `1.5.18.198`.
- APK: `versionName=1.5.18`, `versionCode=198`, Signature Scheme v2 PASS;
  сертификат совпадает с предыдущим release. AAB JAR integrity PASS.

## Backup и rollback

- До mutation создан encrypted backup
  `magicmusiccrm-staging-20260828T090425Z.tgz.enc`, `174 656` bytes,
  SHA-256
  `3AAEA38E0E819CD8E64E9A38C97CA9C273C8045BE04A06E653C6B262A3AF4AF7`.
  Off-host hash совпал; изолированное восстановление вернуло migration `0140`
  и counts `12/1/3/1/1`.
- После rollout создан encrypted backup
  `magicmusiccrm-staging-20260828T095024Z.tgz.enc`, `174 688` bytes,
  SHA-256
  `BC313EA43894A6F2CD0B57145A4DBE8559B981A5AE7C73982AD28ACE1EB4809D`.
  Off-host hash совпал; изолированное восстановление вернуло migration `0141`
  и counts `12/1/3/1/1`.
- Предыдущий image сохранён как
  `magicmusiccrm-server:rollback-pre-1.5.18-198-20260828T0943Z`.
- Manifest build `197` и прежняя release history сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260828T0947Z-pre-198`.
- Первый cutover автоматически вернул прежний healthy runtime: deploy-only
  проверка ожидала неверное текстовое имя уже успешно применённой migration
  `0141`. После исправления проверки повторный cutover PASS; down migration и
  удаление данных не выполнялись.

## Production verification

- Runtime image/revision/version: exact candidate / `744959ef` /
  `1.5.18+198`; restart count `0`, health `healthy`.
- Public live/ready: `200/200`; readiness `ok`, migration `0141`, обязательные
  workers и v4 domains `ok`.
- V7 reconciliation до повторного cutover и дважды после него вернула `0`
  issues; legacy aggregate gaps `0`, repair ledger `1`.
- Platform outbox pending/dead-letter `0/0`; свежие fatal, unhandled,
  Internal Server Error и Caddy `5xx` отсутствуют.
- `latest.json` и `latest-v2.json` идентичны: `1.5.18+198`, build `198`,
  точный Windows ZIP URL/SHA-256. Public release history содержит `38`
  выпусков и начинается с build `198`.
- Все четыре public URL вернули HTTP `200` и точные размеры. GitHub-computed
  digests и размеры четырёх assets совпали с локальными и production-файлами.

## Клиентские артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 695 089` | `901AE79D33D059C8B8AB8BB6BE644C9FF67B025E79E69938D5B13353BAEB5A01` |
| Windows Setup | `15 486 866` | `47ED86F254785054FA847464555077DF60C8BB2D6F8CE31C54C5244EE7B3AE31` |
| Android APK | `87 154 388` | `8834767C5286E2403FBB21F5F360308AB9BAD48296857798BBD36C7FEA4348AB` |
| Android AAB | `61 031 779` | `751C2A2ED977C9CFCADDD714BF2236FBD920AE6BFB82F256E837553C2A85D079` |

Клиенты build `<198` получают предложение обновиться при запуске, возврате в
приложение или следующей фоновой проверке. AAB собран и опубликован в release
assets; Google Play Console остаётся отдельным ручным каналом и этим rollout не
изменялся.
