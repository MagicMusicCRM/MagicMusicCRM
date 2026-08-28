# Production client hotfix `1.5.19+199`

Дата: `2026-08-28` (МСК)

Результат: **PASS**

## Зафиксированный кандидат

- Functional commit: `644c7321`.
- Release commit: `1e7bf09b52549c73c0c65d1c2896fc880fcbf202`.
- Tag и GitHub Release: [`v1.5.19`](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.19).
- Тип выпуска: client-only; backend image, runtime и database migration не
  изменялись.

## Исправление

- Production workspace снова монтирует общий shell раздела до построения
  содержимого конкретного экрана.
- Для системного администратора восстановлены нормальные Overview и Settings:
  вместо сырого текста, серых заглушек и сломанной геометрии отображаются
  штатные карточки, панели и controls темы Deep Charcoal & Sophisticated Gold.
- Regression покрывает desktop/mobile layout и production role persona.

## Release gates

- `flutter analyze --no-pub`: PASS, замечаний `0`.
- Полный Flutter suite: `1360/1360` PASS.
- Windows device role-persona gate: `6/6` PASS.
- Windows workspace device gate: `4/4` PASS.
- Windows portable и Setup собраны из clean detached worktree exact commit;
  embedded version `1.5.19+199`, Setup ProductVersion `1.5.19.199`.
- APK: package `magic.crm`, `versionName=1.5.19`, `versionCode=199`, target SDK
  `36`, Signature Scheme v2 PASS; signing certificate совпал с предыдущим
  release. AAB JAR integrity PASS.

## Backup и rollback

- До публикации создан encrypted backup
  `magicmusiccrm-staging-20260828T111804Z.tgz.enc`, `175 920` bytes,
  SHA-256
  `4779DD219E8358D9DBC0BFD315E327B108B725A773E694777E6359CB25D070BB`.
- Production и off-host копии совпали. Штатный isolated restore-check в
  одноразовый PostgreSQL вернул migration
  `0141_repair_legacy_subscription_aggregate_versions`, users `12`, retained
  administrators `2`; остаточных restore-контейнеров `0`.
- Три предварительных варианта расширенного restore gate остановились только в
  одноразовом окружении: отсутствовал host `pg_restore`, затем был пойман
  переход PostgreSQL от init-процесса к final server, после чего лишняя
  проверка использовала недетерминированный порядок migrations. Production DB
  и volumes не подключались и не изменялись.
- Manifest build `198` и прежняя release history сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260828T112239Z-pre-199`;
  `SHA256SUMS` проверен. Rollback заменяет release history и оба manifest
  атомарными `mv`; build `199` artifacts удалять не требуется.

## Production verification

- `latest.json` и `latest-v2.json` идентичны: version `1.5.19+199`, build
  `199`, точный Windows ZIP URL/SHA-256. Public release history содержит `39`
  выпусков и начинается с build `199`.
- Все четыре public URL вернули HTTP `200`; их потоковые SHA-256, размеры,
  production-файлы и GitHub-computed digests совпали.
- Public live/ready: `200/200`; database, migrations, completion worker,
  outbox и v4 rollout `ok`. Worker due/retry/poison `0/0/0`, outbox
  pending/dead-letter `0/0`.
- API остался на image
  `sha256:5bd6ee44919c5f4f700771c34c33d514d288cead2023fdf329597a9af32b820f`,
  revision `744959efcef31394895a59a7e782d015364caf29`, label `1.5.18+198`,
  migration `0141`, health `healthy`, restart `0`.
- Две read-only V7 reconciliation вернули `issues=[]`; свежие fatal,
  unhandled, Internal Server Error и Caddy `5xx` отсутствуют.
- GitHub Release опубликован как latest, не draft и не prerelease; четыре
  assets проверены через GitHub API.

## Клиентские артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 696 068` | `C2AA76587A51BD8BA794BEA551CEA246CD8F5ACA19EFDBC02CF20149E42CF71B` |
| Windows Setup | `15 485 406` | `E4EA180AAB9E9E5835347FF53E8CC339F4EB60A91DB5146A74EE5D462AA110A8` |
| Android APK | `87 154 528` | `9CABDE835C7CD8C777B46B10253B0E03FD42BC7B61FD2AFF15DAB76A57F7A8CA` |
| Android AAB | `61 031 021` | `AC1B1C3A31B4D5576EA16C5E93A11FAECBDA82365316291DA4C231F40CCA63EB` |

Клиенты build `<199` получают предложение обновиться при запуске, возврате в
приложение или следующей фоновой проверке. Google Play Console остаётся
отдельным каналом и этим rollout не изменялся.
