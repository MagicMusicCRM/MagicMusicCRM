# Production client rollout `1.5.8+188`

Дата: `2026-08-14`

Результат: **PASS**

## Зафиксированный кандидат

- Product fix: `6717d6afff7ae12fc16999d84422220d0f6fdfc7`.
- Release commit и tag `v1.5.8`:
  `a9f8fac90dd524e6961663083ac361caa2176502`.
- Production API не пересобирался: runtime остался
  `magicmusiccrm-server:1.5.7-187-23688482`, healthy, migration `0135`.
- Исправление клиентское: карточки сотрудника и преподавателя без связанного
  аккаунта сохраняют обычные данные без обязательных email/пароля. Создание
  доступа остаётся отдельным явным действием.

## Gates

- `flutter analyze`: PASS, замечаний нет.
- Полный Flutter suite: `799/799`, PASS.
- Windows portable ZIP: embedded version `1.5.8+188`, launch PASS.
- Windows Setup: embedded version `1.5.8+188`, install/launch/uninstall PASS.
- APK: `versionName=1.5.8`, `versionCode=188`, update install PASS.
- Android 15/API 35: `MainActivity` стала top-resumed, экран входа отрисован;
  `AndroidRuntime`, `E/flutter` и `FlutterError` отсутствуют.
- APK Signature Scheme v2: PASS, один signer; certificate SHA-256
  `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
- AAB JAR signature: PASS; тот же release certificate, действителен до
  `2053-10-15`. Self-signed certificate и отсутствие timestamp ожидаемы для
  текущего внутреннего release key.
- RepoWise release diff: `Below typical`, risk percentile `4.1`, low review
  priority. Продуктовый fix ранее оценён как typical/moderate и покрыт
  `system_settings_workspace_test.dart`.

## Артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 531 507` | `5E85D4CD0A5188882E22DD82EDF78CBE1952CAD23FB8B98026A481BF51459C0D` |
| Windows Setup | `15 380 744` | `42BD86E8A36FBE8D4E1DA785DD9C38F11FFB1FE8E0982639C4F1717848F32201` |
| Android APK | `86 246 797` | `9A8E0769ED23C376DBAF2AF906C04E4FE3611ADC55E340166191738335568AAA` |
| Android AAB | `60 604 562` | `2A8BF65A275D944BB670FCC71FD894F1AF4060B99771004366E46CA2E0EB21AF` |

## Backup и rollback

- Перед публикацией создан encrypted backup
  `magicmusiccrm-staging-20260814T101805Z.tgz.enc`, `122 352` bytes,
  SHA-256
  `158AEF2BDA6DBDA7EC7D5707A4271D2745A9A9E98A3627BBBE7DDE63F785409F`.
- Backup скопирован off-host; локальный и remote SHA-256 совпали.
- Предыдущие manifests сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260814T101850Z-pre-188`.
- Rollback клиента: атомарно вернуть оба сохранённых manifest; артефакты build
  `187` оставлены на месте. Backend rollback не требуется, потому что server и
  БД не менялись.

## Production verification

- `latest.json` и `latest-v2.json` идентичны: `version=1.5.8+188`,
  `buildNumber=188`, exact Windows ZIP URL/SHA-256.
- Все четыре production download URL вернули HTTP `200` и точные размеры.
- Windows ZIP полностью скачан через публичный URL; SHA-256 совпал с manifest.
- GitHub Release [v1.5.8](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.8)
  опубликован как Latest. Все четыре GitHub-computed digest и размера совпали
  с локальными артефактами.
- Public live/ready: `200/200`; API container healthy, restart не выполнялся.
- Post-publish `app.reconcile_v7_commerce()` вернула `0` issues.

Production client rollout завершён; пользователям build `<188` предлагается
обновление при следующем запуске.
