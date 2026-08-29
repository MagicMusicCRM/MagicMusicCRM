# Production design rollout `1.5.20+200`

Дата: `2026-08-29` (МСК)

Результат: **PASS**

## Зафиксированный кандидат

- Release commit: `9e35dbe9284ebf74ded930c908f3149990483808`.
- Tag и GitHub Release: [`v1.5.20`](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.20).
- Тип выпуска: client-only. Backend image, runtime, migrations и production
  data не изменялись.
- Кандидат собран из clean clone после обнаружения повреждённого локального
  shared Git object store; remote `main` обновлён только fast-forward.

## Изменение

- Production UI переведён на единую светлую систему Warm Ivory & Sophisticated
  Gold с тихой графитовой иерархией и семантическими `AppColor`-токенами.
- Улучшены экран входа, навигация и вкладки, карточки клиентов, задачи,
  расписание, формы и композиция узких экранов.
- Удалены legacy-кнопки назад/вперёд. Рабочие вкладки, хлебные крошки,
  route stack и защита несохранённых форм сохранены.
- Production scope не содержит изменений `server`, migrations, API/services,
  security или shared providers.

## Release gates

- `flutter analyze --no-pub`: PASS, замечаний `0`.
- Полный Flutter suite: `1375/1375` PASS; release history: `5/5` PASS.
- Windows device gates: role personas `6/6`, app launch `2/2`, workspace `4/4`.
- Windows Release embedded version `1.5.20+200`; Setup ProductVersion
  `1.5.20.200`; ZIP integrity PASS.
- APK: package `magic.crm`, `versionName=1.5.20`, `versionCode=200`, min SDK
  `24`, target SDK `36`, Signature Scheme v2 PASS. Signing certificate совпал
  с production release `1.5.19+199`. AAB JAR verification PASS.

## Backup и rollback

- До публикации создан encrypted backup
  `magicmusiccrm-staging-20260828T205739Z.tgz.enc`, `183 584` bytes,
  SHA-256
  `C0BFBF15AC1C4F923DC6DE9D2F698B0A68165DAFDE95CF613499C68252AFDC58`.
- Production и off-host копии совпали. Isolated restore в одноразовый
  PostgreSQL вернул migration
  `0141_repair_legacy_subscription_aggregate_versions`, users `12`, retained
  administrators `2`.
- Manifest build `199` и прежняя release history сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260828T205844Z-pre-200`;
  `SHA256SUMS` проверен.
- Клиентский rollback выполняется атомарным возвратом `latest.json`,
  `latest-v2.json` и `release-history.json` из этого каталога. Сервер и БД для
  такого rollback не меняются.

## Production verification

- `latest.json` и `latest-v2.json` идентичны: version `1.5.20+200`, build
  `200`, exact Windows ZIP URL/SHA-256. Public release history содержит `40`
  выпусков и начинается с build `200`.
- Все четыре public artifacts вернули HTTP `200`; потоковые SHA-256 и размеры
  совпали с локальными и GitHub Release assets.
- Public live/ready: `200/200`; database, migrations, lesson completion worker,
  outbox и v4 rollout `ok`. Worker due/retry/poison `0/0/0`, outbox
  pending/dead-letter `0/0`.
- API остался на image
  `sha256:5bd6ee44919c5f4f700771c34c33d514d288cead2023fdf329597a9af32b820f`,
  revision `744959efcef31394895a59a7e782d015364caf29`, label `1.5.18+198`,
  migration `0141`, health `healthy`, restart `0`.
- Две read-only V7 reconciliation вернули `{"backfill":null,"issues":[]}`.
- GitHub Release опубликован как latest, не draft и не prerelease; четыре
  assets проверены через GitHub API.

## Клиентские артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 713 014` | `A9B3DEEF1A3C8F0C3A79156003FFD6EDDD3E9E7A2656ED993CEA51E20F3E4DE0` |
| Windows Setup | `15 504 087` | `4DD0C5AE1AC218972279773C782E32B0445A91CB3EF076BA2AD56C36AA2EC95E` |
| Android APK | `87 416 932` | `2848BA516CFFAF88244774737CF8BC2845A60320F027EB0911879D73DC15E6B5` |
| Android AAB | `61 088 772` | `3C26C5F7F601A7E12AE5E6C09413D03507FF08B8A63672C5893F17EC324F5356` |

Клиенты build `<200` получают предложение обновиться при запуске, возврате в
приложение или следующей фоновой проверке. Google Play Console этим rollout не
изменялся.
