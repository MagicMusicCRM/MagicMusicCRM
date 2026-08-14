# Production client rollout `1.5.9+189`

Дата: `2026-08-14`

Результат: **PASS**

## Зафиксированный кандидат

- Product fix: `58e85299`.
- Release commit и tag `v1.5.9`: `e783095308ed6b20f85331e221053b3bdab45464`.
- Production API не пересобирался: runtime остался
  `magicmusiccrm-server:1.5.7-187-23688482`, healthy, migration `0135`.
- Исправление клиентское: актуальный unified CRM endpoint возвращает одно поле
  с Lead/Student visibility без legacy `entityType`; клиентская API-граница
  теперь сохраняет запрошенную проекцию. Благодаря этому варианты поля
  `Кем приходится` доступны и при добавлении, и при редактировании контактного
  лица.

## Gates

- `flutter analyze`: PASS, замечаний нет.
- Полный Flutter suite: `801/801`, PASS.
- Точечные regressions создания/редактирования contact person: `2/2`, PASS.
- RepoWise release diff: `Typical`, risk percentile `47`, review priority
  `moderate`; непокрытых изменённых строк рабочего кода нет.
- Windows portable ZIP: embedded version `1.5.9+189`, launch PASS.
- Windows Setup: install/version readback/launch/uninstall PASS.
- APK: `versionName=1.5.9`, `versionCode=189`, update install `188 -> 189` PASS.
- Android 15/API 35: launcher resolved to
  `magic.crm/com.magicmusiccrm.magic_music_crm.MainActivity`, top-resumed;
  `AndroidRuntime`, `FATAL EXCEPTION`, `E/flutter` и `FlutterError` отсутствуют.
- APK Signature Scheme v2: PASS, один signer; certificate SHA-256
  `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
- AAB JAR signature: PASS; release certificate действителен до `2053-10-15`.

## Артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 531 750` | `006DB8AD5F47A9DECE217EA966D8B42459175C911383D8F228DD8997CB524ECB` |
| Windows Setup | `15 379 802` | `A91E0749034D7BA975A4A991A6F7F5F08969EDC96FCFCBA245F85F4A4A7671AE` |
| Android APK | `86 246 797` | `77B5AE1C3505614FAFC1B32B1191A04E899068E568B7E271C0AFEB7AD9780929` |
| Android AAB | `60 607 186` | `A9F3435AF473A05EEBA91C8111EF785A3A79AB235F495EB48396FD4379CE0AEF` |

## Backup и rollback

- Перед публикацией создан encrypted backup
  `magicmusiccrm-staging-20260814T134052Z.tgz.enc`, `129 600` bytes,
  SHA-256
  `7AE3D2672B7A75BEAED9546D6BCC49A9E0F0C1EF98D8F1EB865EE8998334D083`.
- Backup скопирован off-host в `MagicMusicCRM Backups`; локальный и remote
  SHA-256 совпали.
- Предыдущие manifests сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260814T134343Z-pre-189`.
- Rollback клиента: атомарно вернуть оба сохранённых manifest; артефакты build
  `188` оставлены на месте. Backend rollback не требуется, поскольку server и
  БД не менялись.

## Production verification

- `latest.json` и `latest-v2.json` идентичны: `version=1.5.9+189`,
  `buildNumber=189`, exact Windows ZIP URL/SHA-256.
- Все четыре production download URL вернули HTTP `200` и точные размеры.
- Windows ZIP полностью повторно скачан через public URL; SHA-256 совпал с
  manifest.
- GitHub Release [v1.5.9](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.9)
  опубликован как Latest. Все четыре GitHub-computed digest и размера совпали
  с локальными артефактами.
- Public live/ready: `200/200`; API container healthy, restart `0`.
- Post-publish `app.reconcile_v7_commerce()` вернула `0` issues; scan свежих
  API logs не обнаружил `fatal`, `unhandled` или `Internal Server Error`.

Production client rollout завершён; пользователям build `<189` предлагается
обновление при следующем запуске.
