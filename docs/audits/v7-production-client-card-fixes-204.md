# MagicMusicCRM `1.5.24+204` — production release evidence

Дата выпуска: 2026-08-30

Final commit: `43a0651fc1be0c6b06a34a2eb375cf40d016cb54`

Contact-aware rollback: `40015290cacc5a1818727fa9e64c85b97e3f7d52`

## Выпущенный контур

- Контактная почта хранится в `app.students.contact_email` и не изменяет login
  identity в `app.users`.
- Направление сохраняется по актуальному каноническому справочнику; старые
  typed custom fields не вызывают ложную ошибку справочника.
- Сохранение email не создаёт неявный app access. Явное приглашение связано с
  student id и SHA-256 актуального адреса; stale A→B invitation fail-closed.
- Migration `0145_student_contact_email` проверяет schema contract и имеет
  fail-closed down guard.

## Test и build gates

- Flutter full: `1456/1456`; analyze: PASS.
- Backend full: `269/269` suites, `3387/3387` tests; typecheck/build: PASS.
- Targeted PostgreSQL contact/auth gate: `51/51`.
- Windows release build: PASS; EXE `1.5.24+204`; Setup `1.5.24.204`.
- Android: package `magic.crm`, `versionCode=204`, `versionName=1.5.24`;
  APK v2 signature PASS, AAB `jar verified`.

## Production rollout

- Base: `1.5.23+203`, revision `4804da078efeddb4b6538de187321a2e79d55181`,
  migration `0144_direct_subscription_payment_isolation`.
- Stage 1: exact bridge image
  `magicmusiccrm-server:1.5.24-204-bridge-40015290cacc`; migration `0145`.
- Stage 2: exact final image
  `magicmusiccrm-server:1.5.24-204-43a0651fc1be`, image
  `sha256:583a2a23c69567fa318c860d568a071681bf4370b58104f170ad428d23ed55a9`.
- Final readiness: healthy, restart `0`, OOM `false`, latest migration `0145`.
- V7 reconciliation twice: `{"backfill":null,"issues":[]}`.
- Fresh API errors and Caddy 5xx after cutover: `0/0`.
- Rollback after public bridge traffic: only exact bridge `40015290`; build 203
  is not an allowed database rollback target.

## Backup и rollback evidence

- Pre-cutover encrypted backup:
  `magicmusiccrm-staging-20260830T121213Z.tgz.enc`, SHA-256
  `0b41ec2280cced16f90ac5b7b1d0a076a287fd8b0bad7f89ded673d3d2bd45f4`.
- Post-deploy encrypted backup:
  `magicmusiccrm-staging-20260830T121832Z.tgz.enc`, `201664` bytes, SHA-256
  `f5dc5ec072d894df75cb7943df195fca2ca210221dd686ea28fc18262a538793`.
- Post backup и sidecar скопированы off-host в
  `C:\Users\Alinka\Documents\MagicMusicCRM Backups\2026-08-30`; checksum match.
- Isolated restore final `43a0651f` + rollback bridge `40015290`: PASS.
- Client manifest rollback snapshot:
  `/opt/magicmusiccrm/releases/client-manifest-rollback-203-20260830T121900Z`.

## Опубликованные artifacts

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `MagicMusicCRM-1.5.24-204-windows-x64.zip` | 19787067 | `acba52c895f241434754511066482a7f05ad0acbbf6192c5a512745678218421` |
| `MagicMusicCRM-1.5.24-204-Setup.exe` | 15556854 | `82b06dda48570ec7bc6468313578b546552f9f2d3fd3bcb9987fd1a7394974f4` |
| `MagicMusicCRM-1.5.24-204.apk` | 87696384 | `0bb4753e221838e3edb9b0aece895d17afa5042a2fdf46656f0836ebe189924d` |
| `MagicMusicCRM-1.5.24-204.aab` | 61268687 | `c34e0efcff9be92c4ae706ff82df3ec39c46e4584f31f43f3f0ba2a6e3a7715e` |

Оба public manifest показывают `1.5.24+204`; все четыре artifacts повторно
скачаны через HTTPS, их hashes совпали с локальными. GitHub Release:
`https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.24`.
