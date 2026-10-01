# Release 1.5.53+233 — 02.10.2026 (Europe/Moscow)

Владелец прямо разрешил выпуск клиента и сервера. Исходник кандидата:
`d22915db72f477c9f1bbb89aca6204c9dd98e068`, tag `v1.5.53`.
Рабочая копия — `codex/ui-release-232`; исходная импортированная копия не менялась.
Статус: выпущен 02.10.2026, около 00:51 Europe/Moscow. API, оба update-канала,
история выпуска и публичный GitHub Release проверены.

## Состав и проверенная граница

Типы списания и оплаты преподавателю в группе, наследование настроек в постоянном
расписании, разовое занятие всем активным участникам. Настройки персонала и
филиалов перенесены в связанные карточки, группы — в отдельный раздел. Улучшены
CRM и навигация настроек, компактная строка календаря, перенос времени занятия
у преподавателя, сведения о филиале и абонементе в выборе клиента.

Полный backend: 324 suites / 4167 PASS, 0 skip; fingerprint
`3643c669d2d77ac47d6d2ad557b779a242647913d33ea94ebb99ff714d3d7538`
совпадает после коммита и перед выпуском. Flutter: 1883 PASS / 4 штатных skip,
анализ без замечаний. Native: 11 шагов групп и 57 шагов расписания; HTTP:
28 и 23 сценария соответственно, без серверных ошибок. Эти прогоны сделаны на
проверенном исходнике до повышения версии и добавления истории выпуска; повторный
полный прогон на одном только изменённом номере версии не заявляется.
Исходник поведения после этих прогонов не менялся. Подробности и команды:
[группы и замеры](group-defaults-performance-2026-10-01.md).

Windows 233 собран с production API, первый кадр и 5 секунд без сбоя PASS.
Setup/ZIP упакованы; все 27 runtime-файлов ZIP побайтно совпадают.
APK/AAB собраны с production API; versionCode 233, versionName 1.5.53,
сертификат SHA-256
`0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
APK установлен на собственный offline QA emulator, экран входа проверен,
crash log пуст. Это не авторизованная ручная приёмка реальных данных владельца.

## Production до переключения, backup и откат

Прочитан непосредственно перед выпуском: API revision
`0d859b4eea335cfdfaa9f561502cd5d591360f57`, image
`sha256:111d8d047415179462e8da5176e3fab01c9378c957aad4f54013b5837cab6e36`,
healthy, restart 0; client 1.5.52+232, schema 0161, PostgreSQL 16.4.
CHECK/function hashes и trigger columns прочитаны из реальной БД и совпадают
с параметрами canonical deploy. Readiness OK, pending/deadLetter 0/0.

Pre backup `magicmusiccrm-staging-20261001T213801Z.tgz.enc`, SHA-256
`e459e7679efc396cad1262d967636b19511345354695183a01967a9cb3fff519`.
Внешняя копия — `C:/Users/Alinka/Documents/MagicMusicCRM Backups/release-233`;
SHA совпал. Восстановление в изолированный PostgreSQL 16.4, forward migration
0162 и reconciliation кандидата PASS. Live database при проверке не менялась.

Кандидат `magicmusiccrm-server:1.5.53-233-candidate`, image ID
`sha256:533a0aba265cb16051b6b339e8645f3d0583ee297d172e49406710b03147bee8`.
Неизменённый runtime 232 использован повторно; заменены проверенный `dist` и
миграции, новые зависимости не устанавливались.

Первый restore drill с исходным образом 232 выявил, что migration runner
отвергает неизвестную 0162. Этот результат не считается PASS.
Recovery `magicmusiccrm-server:1.5.52-232-recovery-0162`, image ID
`sha256:0c96f188dc281b3e97bf628c00ededb7c0ba07159bab30aa713ec01db14e5c96`:
прежний API 232 плюс только reviewed up/down SQL 0162 из кандидата.
Migration compatibility, отсутствие повторных миграций, reconciliation и
read-only schema probe на восстановленной новой БД PASS. Кандидат и recovery
отдельно прошли image gate: fail-closed configuration, live/ready/healthcheck,
degraded readiness HTTP 503; synthetic ресурсы удалены.

Откат сохраняет новую схему и всю историю. Штатные скрипты в
`/opt/magicmusiccrm/releases/1.5.53-233`: canonical `cutover.sh`,
обратное переключение `recover-api-232.sh`, `restore-232.sh` возвращает оба
update-канала и историю 232. Новые функции групп требуют API 233: уже установленный
клиент 233 при recovery не получает их; вместе с API восстанавливаются каналы
клиента 232. Старую БД поверх живой истории не восстанавливать, SQL down не выполнять.

Локальные ошибки подготовки: замена номера затронула путь worktree и pinned image
в копиях старых release-скриптов; исправлены конкретные поля до выполнения шагов.
Ошибка имени Android Activity исправлена по фактическому APK badging.
Системный Python alias заменён bundled Python для проверки ZIP. Эти ошибки
не требовали изменений приложения или production-данных.

`origin/main` прочитан: `532a68f224dda750680d32b345c82377cca53311`.
Он не является текущим production source. Выпуск фиксируется точным immutable
tag и отдельной release-веткой; автоматическая замена main не выполнялась.

## Команды и локальное evidence

Windows: `flutter build windows --release --target=lib/main.dart
--dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api`.
Android: такие же target/API flags для `flutter build apk --release` и
`flutter build appbundle --release`. Подписи проверены `apksigner verify`,
`jarsigner -verify`, `keytool -printcert -jarfile`.
Образы: `scripts/v7_production_image_gate.ps1` с точным image/revision,
`-ExpectedMigrationId 0162_group_lesson_defaults` и отдельными synthetic именами.
Backup: штатный `backup-staging.sh`, затем
`verify-release-backup-compatibility.sh` с точными candidate/recovery image,
version/revision, новым archive и PostgreSQL 16.4.

Evidence: `dist/release233/`, включая manifest, ZIP comparison, native smoke,
image gates, backup/restore logs и actual production contract. Секреты и backup
не включаются в Git. Публикация использует проверенные хеши единственной упаковки.

## Фактический выпуск и проверка после переключения

Canonical `deploy-api-release.sh` завершился `DEPLOY_API_RELEASE|PASS`:
API `d22915db72f477c9f1bbb89aca6204c9dd98e068`, image ID кандидата совпадает,
schema `0162_group_lesson_defaults`, healthy, restart 0. CHECK/function hashes
и trigger columns после переключения не изменились. Публичная readiness OK,
outbox pending/deadLetter 0/0; reconciliation `{"backfill":null,"issues":[]}`.
Данные не исправлялись через backfill или ручное удаление истории.

Оба канала `latest.json` / `latest-v2.json` и release-history — 1.5.53+233.
Четыре публичных файла доступны с правильными размерами; ZIP/APK скачаны по
публичным URL, SHA-256 совпали. GitHub Release опубликован из проверенного draft;
все четыре asset digest и размера совпадают с manifest.
[Публичный выпуск](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.53).
На пользовательском компьютере запущен Windows Release 1.5.53+233 с обычным
профилем; через 5 секунд процесс работал. Это не подтверждение ручной приёмки
владельцем всех сценариев с реальными данными.

Post backup `magicmusiccrm-staging-20261001T215114Z.tgz.enc`, SHA-256
`b4853456acf59d14fc379c89dda3f69ca52057c53a990a645f4964e8166e0ac9`.
Внешняя копия и checksum sidecar сохранены в той же папке release-233,
SHA совпал. Восстановление post backup на candidate/recovery и reconciliation
PASS. Первое одновременное копирование двух remote paths остановилось на
проверке имени SCP; отдельные копирования завершились и хеш архива проверен.

Сохранённое evidence: [manifest](release-233-evidence/artifact-manifest.json),
[публичная публикация](release-233-evidence/public-publication.json),
[готовность](release-233-evidence/public-readiness.json),
[GitHub](release-233-evidence/github-release.json),
[cutover](release-233-evidence/production-cutover.txt),
[post reconciliation / backup](release-233-evidence/production-post.txt),
[restore pre](release-233-evidence/restore-pre.txt),
[restore post](release-233-evidence/restore-post.txt),
[recovery manifest](release-233-evidence/recovery-manifest.json).
