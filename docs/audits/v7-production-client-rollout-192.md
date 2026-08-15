# Production client rollout `1.5.12+192`

Дата: `2026-08-15` (МСК)

Результат: **PASS**

## Зафиксированный кандидат

- Исправление интерфейса: `fe68388a`.
- Release commit и tag `v1.5.12`: `290c01ca`.
- GitHub Release:
  <https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.12>.
- Выпуск клиентский. Сервер остался на image
  `magicmusiccrm-server:1.5.11-191-bcb26f36`, migration head
  `0137_lesson_resource_bookings`.

## Изменение

- Английские и технические подписи пользовательского интерфейса заменены
  коротким русским текстом.
- Сообщения API и transport-ошибок проходят через общий безопасный
  русскоязычный преобразователь и больше не показывают пользователю backend
  codes, stack traces или английские исключения.
- Подписи анализатора расписания, расчёта конфликтов, доступов, отчётов и
  настроек приведены к единому русскому словарю.
- Добавлены policy-тесты, запрещающие возврат известных технических фраз и
  прямой вывод caught error в UI.

## Release gates

- `flutter analyze`: PASS, замечаний нет.
- Полный Flutter suite: PASS.
- Точечные тесты ошибок, UI policy, расписания, доступов, отчётов, файлов,
  уведомлений и форм: PASS.
- RepoWise release diff: `Elevated`, risk percentile `92.9`, review priority
  `high`. Причина: механическая очистка текста затронула `136` файлов. Все
  Flutter-тесты были повторно запущены на exact release candidate.
- Gitleaks по двум release-коммитам: `0` leaks.
- Windows portable: embedded version `1.5.12+192`, launch PASS.
- Windows Setup: current-user install, version readback, launch и uninstall
  PASS.
- APK: `versionName=1.5.12`, `versionCode=192`, Signature Scheme v2 PASS,
  certificate SHA-256
  `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
- Android API 35 update `191 -> 192`, cold launch и top-resumed activity PASS;
  `AndroidRuntime`, `FATAL EXCEPTION`, `E/flutter` и `FlutterError` отсутствуют.
- AAB JAR signature integrity PASS; сертификат действителен до `2053-10-15`.

## Backup и rollback

- Перед публикацией создан encrypted backup
  `magicmusiccrm-staging-20260815T101711Z.tgz.enc`, `136 000` bytes,
  SHA-256
  `2D3B15091A83926E6487440AA77860DA65BBE2730097C11F2CA59CD33561DE14`.
- Backup скопирован off-host в `MagicMusicCRM Backups`; локальный и remote
  SHA-256 совпали.
- Этот же архив расшифрован и полностью восстановлен в изолированный
  PostgreSQL: migration `0137_lesson_resource_bookings`, users `11`, два
  обязательных сохраняемых аккаунта подтверждены.
- Предыдущие manifests сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260815T102049Z-pre-192`;
  SHA-256 обоих файлов
  `A2B146F501F2955C851CF8D3AB92666FA6835E8DEB7323C50329ACA64BBB604B`.
- Rollback клиента: атомарно вернуть оба сохранённых manifest. Артефакты build
  `191` оставлены на месте. Backend rollback не требуется.

## Production verification

- `latest.json` и `latest-v2.json` идентичны: `version=1.5.12+192`,
  `buildNumber=192`, exact Windows ZIP URL/SHA-256.
- Все четыре production download URL вернули HTTP `200` и точные размеры.
- Windows ZIP полностью повторно скачан через public URL; SHA-256 совпал с
  manifest.
- GitHub Release опубликован как ready и Latest. GitHub-computed digests и
  размеры всех четырёх assets совпали с локальными и production-файлами.
- Public live/ready: `200/200`; API container healthy, restart `0`.
- Двойной post-publish reconciliation вернул `issues=[]` / `issues=[]`.
- В свежих API logs отсутствуют `FATAL EXCEPTION`, `unhandledRejection`,
  `uncaughtException` и `Internal Server Error`.

## Артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 544 721` | `A158E2BD003454EA4FFA8129993BB2A9AA0919BFBBE7315FD06D8DDF32083596` |
| Windows Setup | `15 387 671` | `519982514A52583718DF60250E86E62B2AA83A97E7A8B6212754495D7F29ABDB` |
| Android APK | `86 279 561` | `EB4E5585B49B930F33461117225D66C5827D284EDCA39CFECED0F6C992D22D8D` |
| Android AAB | `60 651 031` | `6BDDF2303F6FFBA9BD9AF3B9B95FA34A78769D7A427D62609B80DE9663C60BBB` |

Production client rollout завершён. Пользователям build `<192` предлагается
обновление при следующем запуске.
