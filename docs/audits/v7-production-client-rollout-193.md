# Production client rollout `1.5.13+193`

Дата: `2026-08-15` (МСК)

Результат: **PASS**

## Зафиксированный кандидат

- Release commit и tag `v1.5.13`: `4da10125`.
- Исправление совместимости publisher со старой историей: `0786e440`.
- Draft PR: <https://github.com/MagicMusicCRM/MagicMusicCRM/pull/18>.
- GitHub Release:
  <https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.13>.
- Выпуск клиентский. Сервер остался на image
  `magicmusiccrm-server:1.5.11-191-bcb26f36`, migration head
  `0137_lesson_resource_bookings`.

## Изменение

- Версия приложения всегда видна слева внизу на Windows.
- Нажатие на версию открывает русский раздел «Обновления» с текущим выпуском
  и полной историей из `33` версий.
- Новая версия проверяется при запуске, возврате в приложение, каждые 15 минут
  и вручную.
- О доступном обновлении сообщает только золотая точка на кнопке версии.
- Remote history имеет bundled fallback и публикуется до переключения двух
  update manifest.
- Пользовательские тексты истории проверяются на отсутствие английских слов и
  длинного тире.

## Release gates

- `flutter analyze --no-pub`: PASS, замечаний нет.
- Точечные update-тесты: `43/43`, PASS.
- Полный Flutter suite: `826/826`, PASS.
- PowerShell AST, JSON parse и `git diff --check`: PASS.
- RepoWise release diff: `Elevated`, risk percentile `93.5`, review priority
  `high`. Причина: новый update center и полная история затронули `20` файлов
  и добавили `1965` строк. Exact candidate прошёл полный suite и device gates.
- Gitleaks для release и publisher fix: `0` leaks.
- Windows portable: embedded version `1.5.13+193`, launch PASS.
- Windows Setup: Inno Setup `6.7.3`, current-user install, version readback,
  launch и uninstall PASS.
- APK: `versionName=1.5.13`, `versionCode=193`, Signature Scheme v2 PASS,
  один signer, certificate SHA-256
  `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
- Android API 35 update `192 -> 193`, cold launch и top-resumed activity PASS;
  `AndroidRuntime`, `FATAL EXCEPTION`, `E/flutter` и `FlutterError` отсутствуют.
- AAB JAR signature integrity PASS; сертификат действителен до `2053-10-15`.

## Backup и rollback

- Перед публикацией создан encrypted backup
  `magicmusiccrm-staging-20260815T140032Z.tgz.enc`, `140 208` bytes,
  SHA-256
  `9A5FA94B631D8DBFBDAA2A13A495B0D8F6C5EDABEA7CAFC965154921ED21A46F`.
- Backup скопирован off-host в `MagicMusicCRM Backups`; локальный и remote
  SHA-256 совпали.
- Этот же архив расшифрован и восстановлен в изолированный PostgreSQL:
  migration `0137_lesson_resource_bookings`, users `12`, два обязательных
  сохраняемых аккаунта подтверждены.
- Предыдущие manifests сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260815T140021Z-pre-193`;
  SHA-256 каждого файла
  `0DBA7C606524F6A6821D6592F3771FA68EED9F0A872510571CEF46BD15D38C73`.
- Rollback клиента: атомарно вернуть оба сохранённых manifest и переместить
  новый `release-history.json` в rollback-каталог. Артефакты build `192`
  оставлены на месте. Backend rollback не требуется.

## Production verification

- `latest.json` и `latest-v2.json` идентичны: `version=1.5.13+193`,
  `buildNumber=193`, exact Windows ZIP URL/SHA-256.
- Public release history вернула `1.5.13+193` первой записью и `33` выпуска.
- Все четыре production download URL вернули HTTP `200` и точные размеры.
- Windows ZIP полностью повторно скачан через public URL; SHA-256 совпал с
  manifest.
- GitHub Release опубликован как ready и Latest. GitHub-computed digests и
  размеры всех четырёх assets совпали с локальными и production-файлами.
- Public live/ready: `200/200`; API container healthy, restart `0`.
- Первый post-publish reconcile обнаружил две связанные legacy-записи,
  созданные в `2026-08-15 12:36 UTC` после предыдущего чистого gate:
  subscription без funding metadata и payment без client-payment record.
- Штатный транзакционный `backfill_v7_commerce()` добавил `1` subscription и
  `1` payment backfill, `reviewRows=0`, без удаления истории. Два последующих
  reconciliation вернули `issues=[]` / `issues=[]`.
- В свежих API logs отсутствуют `FATAL EXCEPTION`, `unhandledRejection`,
  `uncaughtException` и `Internal Server Error`.

## Артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 556 407` | `623D93C35276B32780540DC366F513CC3F544AAD005B90FCDBF3089294E9E574` |
| Windows Setup | `15 396 695` | `5CADF7DE9E73302679EE492A276DEE00D9A45965E3E6C625DE95A95828000913` |
| Android APK | `86 284 596` | `1A90ED8D2AE19A0B8E5FF713AE3A6C6E437D7BA8309DC9CCB1EE89B35E64D726` |
| Android AAB | `60 660 449` | `4E4F1E694519B9C7E66800D44A1A90E3CB80155F01E4186C3CDC5F852A4CBDC2` |

Production client rollout завершён. Пользователям build `<193` предлагается
обновление при запуске, возврате в приложение или следующей фоновой проверке.
