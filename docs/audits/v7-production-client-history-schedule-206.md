# MagicMusicCRM `1.5.26+206` — production release evidence

Дата выпуска: 2026-08-30

Final commit: `e5503e511c9cbe9871e9f8dd644550c391cba716`

Rollback commit: `f005bf5ecb72055a97f4a987f045124d1cc2fc21`

## Выпущенный контур

- Фильтр расписания «Все филиалы» показывает все филиалы, доступные текущей
  роли, и не подменяется одним выбранным филиалом.
- Часовые пояса филиалов и локальная дата расписания обрабатываются без
  смещения на границах суток и переходах времени.
- В карточке клиента осталась единая человекочитаемая история. По умолчанию
  показаны последние 10 событий, остальные раскрываются по запросу.
- Пустой раздел прогресса использует общий аккуратный empty state.
- Внутренняя история, заметки и финансовые проекции повторно проверяют текущую
  роль в БД и не доверяют устаревшим JWT claims.

## Test и build gates

- Flutter full: `1471/1471`; analyze: PASS.
- Backend full: `271/271` suites, `3405/3405` tests; typecheck/build: PASS.
- Deploy contract, DB contract, behavior и backup compatibility contract: PASS.
- Production-like gate: migration `0145_student_contact_email`, reconciliation
  `issues=[]`.
- Exact image gate: invalid configuration fail-closed, healthy readiness PASS,
  degraded readiness HTTP `503` PASS.
- Windows release: EXE `1.5.26+206`, Setup `1.5.26.206`.
- Android: package `magic.crm`, `versionCode=206`, `versionName=1.5.26`;
  APK v2 signature PASS, AAB `jar verified`.

## Production rollout

- Rollback image: `magicmusiccrm-server:1.5.25-205-f005bf5ecb72`.
- Final image: `magicmusiccrm-server:1.5.26-206-e5503e511c9c`, image
  `sha256:d666238e2456cd178d4d6b7261b58eecadba89e1b37eb2c13c09069aba24f52f`.
- Guarded cutover: `DEPLOY_API_RELEASE|PASS`; migration осталась
  `0145_student_contact_email`.
- Final runtime: healthy, restart `0`, OOM `false`.
- V7 reconciliation дважды: `{"backfill":null,"issues":[]}`.
- Fresh exhausted email / stale invitation после readiness: `0/0`.
  Одна историческая exhausted-запись датирована `2026-08-13` и не относится к
  релизу.
- Свежие API ошибки и Caddy 5xx после readiness: `0/0`.

## Backup и rollback evidence

- Pre-cutover encrypted backup:
  `magicmusiccrm-staging-20260830T162421Z.tgz.enc`, `206240` bytes, SHA-256
  `22d97b70c57430c73719178eb33532d081afea09617534d41e73b964faf97c9f`.
- Post-deploy encrypted backup:
  `magicmusiccrm-staging-20260830T162811Z.tgz.enc`, `206224` bytes, SHA-256
  `a0172e05ff7902b19798fa6117214bd7a0bc39287d4a0264d8575ae91eeb4b0c`.
- Оба backup и sidecar скопированы off-host в
  `C:\Users\Alinka\Documents\MagicMusicCRM Backups\2026-08-30`.
- Оба backup прошли isolated candidate/rollback restore для `1.5.26+206` и
  `1.5.25+205`.
- Client manifest rollback snapshot:
  `/opt/magicmusiccrm/releases/client-manifest-rollback-205-20260830T162904Z`.

## Опубликованные artifacts

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `MagicMusicCRM-1.5.26-206-windows-x64.zip` | 19785590 | `55402fe06372d328940e26c8e4f8794d78e48a43dc8b261ec5a6e049588259be` |
| `MagicMusicCRM-1.5.26-206-Setup.exe` | 15558761 | `60b3b32a21452d7b22e5b6576a4f7de9b243ae3cd63ec8f8aed4679b675f45be` |
| `MagicMusicCRM-1.5.26-206.apk` | 87680300 | `9b54a615c6b6c61888b29966371750eab4f6844477cd10bc42b2c376c1443208` |
| `MagicMusicCRM-1.5.26-206.aab` | 61271644 | `a33df99ad79e7e2ef97f5bc87bb37b18dfbe6a1abeb3023155c620bfe50d84aa` |

Оба public manifest показывают `1.5.26+206`; release history начинается с
build `206`. Все четыре artifacts повторно прочитаны через HTTPS и совпали с
локальными по длине и SHA-256. GitHub Release:
`https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.26`.
