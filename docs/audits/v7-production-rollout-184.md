# Production rollout `1.5.4+184`

Дата: `2026-08-13`

Результат: **PASS**

Owner mega-UAT: **IN PROGRESS**, этим rollout не закрыта

## Зафиксированный кандидат

- Runtime source revision: `11cf8e36177e95ca4f571d4d566570e9f1001625`.
- Последующее ops-only исправление backup: `2e104f3b451fb8080d44104e230b9e9e45123e27`.
- GitHub Release: `v1.5.4`, target runtime revision `11cf8e36`.
- Production image:
  `sha256:eee82d6cacf01fb875020e9dd1fea76ac870f81b6765b59bbb74b1d4576285a2`.
- OCI version/revision/user: `1.5.4+184`, `11cf8e36…`, `magiccrm`.
- Migration: `0132_app_registration_source`.
- Rollback release: `1.5.3+183`, image `sha256:62473bb4…`.

## Пользовательские изменения

- Экран организации обновляет branch catalog из authoritative API при открытии
  и имеет явную кнопку «Обновить»; внешняя clean-start очистка больше не
  оставляет старые филиалы в Riverpod cache до перезапуска приложения.
- Одинаково названные наборы CRM-вариантов помечены как «Карточка лида»,
  «Карточка ученика» или «Карточки лида и ученика» и показывают связанные поля.
- Процентная, фиксированная и почасовая оплата преподавателю вводится прямо в
  основном окне создания/редактирования занятия. Изменение существующего
  занятия проходит через planned settlement revision, а завершённого — через
  settlement correction; фиктивный перенос не создаётся.
- Проекция lesson decision keys защищена backend capability scope и не отдаёт
  преподавательские значения ролям без доступа к ставкам.

## Gates

- Flutter: `793/793`, analyze PASS.
- Backend: `177/177` suites, `1415/1415` tests, typecheck/build PASS.
- Targeted Flutter: `53/53`; targeted Schedule backend: `60/60`.
- Diff check PASS.
- Exact image: invalid production flags fail-closed, migration/live/ready/
  healthcheck PASS, degraded readiness HTTP `503` PASS.

## Client artifacts

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 512 861` | `9C5F30C548087595E386B351CBA67781EC7FBDF523DFBAE561BCB683FA629090` |
| Windows Setup | `15 367 753` | `CCC4388125F3F92EE9AA20EC3A1618C2C5DB961E7ED25F03EF5562BC05B6CDB1` |
| Android APK | `86 214 029` | `DF7E9A10B0321F604DE2D4AC049F50B2A26B4BE81AFD1747EA398742C61485A8` |
| Android AAB | `60 581 199` | `34EFFD0119D947327D583DCBDC5F46A92CFBA38ACDCDC59F93549B22B1D9B367` |

- Windows EXE сообщает FileVersion/ProductVersion `1.5.4+184`; portable launch
  PASS. Setup `/CURRENTUSER` install → version readback → launch → uninstall
  PASS. Distribution остаётся unsigned в рамках принятого owner-риска.
- APK: package `magic.crm`, versionName `1.5.4`, versionCode `184`, minSdk `24`,
  targetSdk `36`, один прежний release signer, APK Signature Scheme v2 PASS.
- Android 15/API 35: update install `183 → 184`, cold launch, resumed
  MainActivity и тёмный login screen PASS; crash buffer, `AndroidRuntime` и
  `E/flutter` пусты.
- AAB JAR signature verification PASS.

## Production server и backup

- До cutover создан encrypted backup
  `magicmusiccrm-staging-20260813T093429Z.tgz.enc`; SHA-256
  `350421C31FCBD93B58DD45F2822BDDD70784EA176C12D302E23E0031D081F062`,
  off-host копия совпала, isolated restore: `0132 / users=2 / retained=2`.
- Backup обнаружил, что host tar не читает intentionally protected storage
  `0700`, owned runtime uid `10001`. Runtime данные не изменялись. Канонический
  `backup-staging.sh` теперь создаёт storage archive через network-isolated,
  read-only helper container с source mount `readonly`.
- После ops fix штатный script создал
  `magicmusiccrm-staging-20260813T094451Z.tgz.enc`, `96 288` bytes, SHA-256
  `0313D947502081FB274CC65E284241E868F5BCBCEBF9BC4C91C1661820B46E13`;
  remote/off-host hash и isolated restore `0132 / 2 / 2` PASS.
- Automatic rollback был вооружён. Candidate сначала прошёл health/reconcile с
  workers disabled, затем повторно с workers enabled; rollback не запускался.
- Post-cutover: exact image healthy, public readiness `5/5`, migration `0132`,
  reconciliation `issues=[]`, clean-start preflight сохранил `2` users,
  `0` branches/rooms/clients/lessons и `10 + 40` CRM fields.

## Публикация

- Оба manifest build `183` сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260813T093934Z-pre-184`.
- `latest.json` и `latest-v2.json` идентичны: `version=1.5.4+184`,
  `buildNumber=184`, Windows ZIP URL и exact SHA-256.
- Все четыре public URL возвращают HTTP `200` и точные размеры; Windows ZIP
  полностью скачан по URL из manifest, SHA-256 совпал.
- GitHub Release `v1.5.4` содержит те же четыре файла; GitHub-computed digests
  совпали с local и production download server.

Production backend и оба client update channels `1.5.4+184` технически
выпущены и проверены. Предметная owner-UAT остаётся отдельной работой.
