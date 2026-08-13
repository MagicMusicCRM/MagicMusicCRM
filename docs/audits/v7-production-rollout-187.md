# Production rollout `1.5.7+187`

Дата: `2026-08-13`

Результат: **PASS**

Owner mega-UAT: **IN PROGRESS**, этим rollout не закрыта.

## Production runtime

- API image: `magicmusiccrm-server:1.5.7-187-0e7411e6`.
- Image ID:
  `sha256:831ea160e7a8d763bdb19e8eb5259d51bea7426fab1f9135b812b195036cdd86`.
- Runtime revision:
  `0e7411e60a105a9912ab6f30789cb29a86496e32`.
- Migration head: `0135_requeue_organization_outbox`.
- API restart count после cutover: `0`.
- Public readiness: `5/5`; reconciliation до и после включения workers:
  `issues=[]`.

## Backup и rollback

- До cutover создан encrypted backup
  `magicmusiccrm-staging-20260813T200427Z.tgz.enc`, `111 440` bytes,
  SHA-256
  `812AF11A627E9391BC9DCD5F26E98253058115F9B32D4F66FEDA02E216554B80`.
- Backup скопирован off-host. Непосредственно предшествующий backup
  `magicmusiccrm-staging-20260813T194837Z.tgz.enc` прошёл isolated restore с
  `migration=0132_app_registration_source`, `users=9`, `retained=2`,
  `dead=1`.
- Старый image сохранён отдельным rollback tag; оба старых update manifest
  сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260813T200603Z-pre-187`.
- Первый cutover корректно активировал automatic rollback из-за ошибки
  deploy-only проверки: compose service назывался `postgres`, а проверка
  обращалась к `db`. Старый API вернулся healthy; данные, migration ledger и
  очередь проверены. После исправления имени сервиса повторный идемпотентный
  cutover завершился PASS.

## Outbox recovery

Production `1.5.4+184` был degraded из-за одного события
`organization.branch.changed`, которое старый worker отправил в dead-letter
после десяти попыток как `UnsupportedPlatformEvent`. `0135` сбросила только его
delivery metadata, а новый worker опубликовал исходный факт.

Post-deploy:

- проблемный event `e2bbb5a3-584e-4778-9035-20631b820922`: `published`;
- platform outbox: `pending=0`, `deadLetter=0`;
- readiness checks database/migrations/workers/V4: `ok`;
- scan свежих API logs: нет `fatal`, `unhandled`, `Internal Server Error` или
  `UnsupportedPlatformEvent`.

## Публикация клиентов

- GitHub Release [v1.5.7](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.7)
  опубликован как Latest и содержит Windows ZIP, Setup, Android APK и AAB.
- GitHub-computed digests и размеры всех четырёх assets совпадают с локальными.
- `latest.json` и `latest-v2.json` идентичны: `version=1.5.7+187`,
  `buildNumber=187`, exact Windows ZIP URL/SHA-256.
- Все четыре production download URL вернули HTTP `200` и точные размеры.
- Windows ZIP полностью скачан через публичный URL; SHA-256 совпал с manifest.

Production backend и оба client update channel технически выпущены и
проверены. Предметная owner-UAT остаётся отдельной работой.
