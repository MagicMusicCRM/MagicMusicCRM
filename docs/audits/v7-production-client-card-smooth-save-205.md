# MagicMusicCRM `1.5.25+205` — production release evidence

Дата выпуска: 2026-08-30

Final commit: `f005bf5ecb72055a97f4a987f045124d1cc2fc21`

Rollback commit: `43a0651fc1be0c6b06a34a2eb375cf40d016cb54`

## Выпущенный контур

- Сохранение карточки, заметки и комментария больше не перезагружает весь
  клиентский экран и не сбрасывает открытые разделы или позицию прокрутки.
- Пустая контактная почта сохраняется как явное удаление, а незавершённый
  адрес блокируется локально без ошибочного запроса на сервер.
- Перед приглашением карточка дожидается сохранения актуального адреса.
  Приглашение без адреса не отправляется.
- Email outbox повторно сверяет student id и SHA-256 текущего контактного
  адреса перед отправкой; устаревшие приглашения завершаются fail-closed.

## Test и build gates

- Flutter full: `1466/1466`; analyze: PASS.
- Backend full: `269/269` suites, `3393/3393` tests; typecheck/build: PASS.
- Исправленные full-suite regression oracles: `47/47` targeted PASS.
- Production-like gate: migration `0145_student_contact_email`, reconciliation
  `issues=[]`.
- Exact image gate и deploy/backup contract gates: PASS.
- Windows release: EXE `1.5.25+205`, Setup `1.5.25.205`.
- Android: package `magic.crm`, `versionCode=205`, `versionName=1.5.25`;
  APK v2 signature PASS, AAB `jar verified`.

## Production rollout

- Base image: `magicmusiccrm-server:1.5.24-204-43a0651fc1be`.
- Final image: `magicmusiccrm-server:1.5.25-205-f005bf5ecb72`, image
  `sha256:35e2ad379cf636266a89f766e8e235ba593760fdb49ec94df3d436dff523f81b`.
- Guarded cutover: `DEPLOY_API_RELEASE|PASS`; migration осталась
  `0145_student_contact_email`.
- Final runtime: healthy, restart `0`, OOM `false`.
- V7 reconciliation дважды: `{"backfill":null,"issues":[]}`.
- Stale invitation / exhausted email outbox gate: `0/0`.
- Свежие API ошибки и Caddy 5xx после cutover: `0/0`.
- Authenticated mutation реальной карточки не выполнялась без отдельной
  управляемой тестовой сессии; production-проверка была read-only.

## Backup и rollback evidence

- Pre-cutover encrypted backup:
  `magicmusiccrm-staging-20260830T140253Z.tgz.enc`, `204256` bytes, SHA-256
  `064d3d25cb7dc76fe78caff86f8bdedde025fa64b03595555fd498bcf0656692`.
- Post-deploy encrypted backup:
  `magicmusiccrm-staging-20260830T140457Z.tgz.enc`, `204272` bytes, SHA-256
  `76bfd3e28c8b84891050fe84d5210474bef5fbcc908a64878aa1a174df6636f1`.
- Оба backup и sidecar скопированы off-host в
  `C:\Users\Alinka\Documents\MagicMusicCRM Backups\2026-08-30`.
- Isolated restore candidate `f005bf5e` и rollback `43a0651f` прошёл для
  pre- и post-deploy backup.
- Client manifest rollback snapshot:
  `/opt/magicmusiccrm/releases/client-manifest-rollback-204-20260830T140532Z`.

## Опубликованные artifacts

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `MagicMusicCRM-1.5.25-205-windows-x64.zip` | 19790806 | `b0f828c56bd019670a135ab38e4aeedf5daa122519fe2f8eea4d65b495980224` |
| `MagicMusicCRM-1.5.25-205-Setup.exe` | 15561961 | `a7d90f2b0c19edabf85b0eb60b7efa66727a1a413b2e884681b3cdf09449f702` |
| `MagicMusicCRM-1.5.25-205.apk` | 87696576 | `060a2983f5f7ebd7b8542a1a05c6753054733efc9422801ca591812def57d42d` |
| `MagicMusicCRM-1.5.25-205.aab` | 61277251 | `097fd3afb03a80d0d9daa0f0c300f3476d1b2fcc2237a6f5217683773bfa9284` |

Оба public manifest показывают `1.5.25+205`; release history начинается с
build `205`. Все четыре artifacts повторно скачаны через HTTPS и совпали с
локальными по длине и SHA-256. GitHub Release:
`https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.25`.
