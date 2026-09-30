# Release 1.5.51+231 — production, 30.09.2026

Статус: **опубликован** по прямой команде владельца «Давай развёртывать в прод». API переключён до публикации клиентов. Итоговая проверка 18:57 по Москве: readiness `ok`, API healthy, restart 0, outbox pending/deadLetter 0/0, reconciliation `issues=[]`.

## Источники и состав

Клиентский commit `a453155ea89ef366ff1bc3f2cec27941897a7549`, annotated tag `v1.5.51` указывает именно на него. Серверный commit `b001956361b9b8c237af6b119bc06dbb23d71400`; server tree совпадает с клиентским commit. Ветка `codex/release-st-completion` опубликована. [GitHub Release](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.51) не draft и не prerelease; четыре asset digest совпали с локальными файлами.

Candidate image `magicmusiccrm-server:1.5.51-231-candidate`, ID `sha256:17e9e0e7a192278c7ee87fc0f231479062ec93eb9187a3259f41969b7fab9a39`. PostgreSQL 16.4, схема осталась `0161_restore_notification_preferences`. Новых миграций относительно 230 нет. Финансовая, учебная и audit-история не откатывалась и вручную не переписывалась.

Исправления и границы тестового покрытия: [кандидат](release-231-candidate.md), [41 требование](release-231-requirements.md). Включены итог ST, исправления RC-01…05, расположение checkbox после полей расчёта, удаление повторяющихся подсказок и доступность Android schedule grid с поиском. Полные suites повторно при deploy не запускались: продуктовые исходники и артефакты не менялись.

## Проверки перед переключением

Наблюдаемая основа: публичные каналы 230, API image `sha256:2f08d092013f01f7b761fc714dd5033b96619b2d01813f0080109d262725f874`, source eb2575d3, healthy/restart 0. Tag 1.5.51 и release directory отсутствовали. Сверены живые CHECK/trigger/function контракты `app.schedule_series`: CHECK `4eb90fa7e35a0a0706fba50767fd205c74e37e8e66e21ef040ad2a79e4df58ae`, canonical function `2e87ee3dff67b9e6e6b891217229f9252cf64c6a3a27ccb8b1fed9952f4b2120`, enabled O/type 23/update columns plan_id,subscription_id. CRLF тела функции нормализован по правилам штатного deploy скрипта.

Все клиентские файлы, release history, оба manifest и архив серверных образов сверены SHA-256 на сервере. После `docker load` проверены точные ID обоих образов. Сертификат APK отдельно сравнен с фактическим APK 230 — совпадает.

## Backup и восстановление

| Момент | Encrypted backup | SHA-256 | Результат |
|---|---|---|---|
| До | magicmusiccrm-staging-20260930T155057Z.tgz.enc | eb1fe23f99219f065158868ca5f4955e12391525031e2ad1a226bb1f199f9528 | Копия вне сервера, hash PASS; restore/reconciliation candidate + recovery PASS |
| После | magicmusiccrm-staging-20260930T155552Z.tgz.enc | 251e11ca68815cc6be21dbdeab6f82a651486126d74d2ef439897f92bf9474b4 | Копия вне сервера, hash PASS; restore/reconciliation candidate + recovery PASS |

Копии: `C:/Users/Alinka/Documents/MagicMusicCRM Backups/release-231`. На сервере: `/opt/magicmusiccrm/backups/encrypted`. Применён штатный `backup-staging.sh` (DB, globals, env, storage внутри encrypted archive), затем `verify-release-backup-compatibility.sh` на PostgreSQL 16.4 в отдельной внутренней Docker network и временном volume. Production volume не подключался к drill. Проверки schema/миграций обоих образов и `issues=[]` завершились успешно; временные контейнеры очищены. Backup/секреты в Git не добавлялись.

Первый многофайловый scp отклонил filename validation; последовательное копирование каждого точного пути прошло без отключения проверки имён. Диагностический повтор backup wrapper остановился на уже существующем rollback directory до создания нового backup; использован первый завершённый архив со сверенным хешем. Эти транспортные/организационные ошибки не скрыты и не считаются сбоем production.

## Cutover и публикация

Штатный `deploy-api-release.sh` вернул `DEPLOY_API_RELEASE|PASS`; проверены точные image/revision, healthy, schema, DB contract, reconciliation и публичная readiness. Временное закрытие Caddy и остановка старого API входят в штатный cutover; после приёмки новый API открыт. Все шесть фоновых workers включены по production-контракту. `DEPLOYED_REVISION` содержит b00195636.

`PROMOTE_MANIFESTS|PASS|build=231|channels=2|artifacts=4`. Оба канала показывают 1.5.51+231 и указывают на Windows ZIP; публичная release history начинается с 231. Четыре URL вернули HTTP 200 и правильные размеры. Публичные ZIP и APK полностью скачаны и совпали по SHA-256. GitHub проверен отдельно по digest всех четырёх assets.

| Файл | Размер, B | SHA-256 |
|---|---:|---|
| MagicMusicCRM-1.5.51-231-Setup.exe | 15729728 | ae174456788c05a838c8ca7f48a627b59cdbecb6e8ec72a2a8e971963973b9fd |
| MagicMusicCRM-1.5.51-231-windows-x64.zip | 19599996 | 1fe02c5fd71ca6666a6d3c3b015e199ec4bb70b48267012a4a4e10143e61d9d0 |
| MagicMusicCRM-1.5.51-231.apk | 91056458 | 9d2ab1eb0a042d1fe5d55959599377f594ae5af2e942240d06e4993e201d310c |
| MagicMusicCRM-1.5.51-231.aab | 62365151 | a8d8b21f89baed5db43a30a5691f0d6da22546edff55db084918de7d1dccb40c |

## Откат и передача

Release directory: `/opt/magicmusiccrm/releases/1.5.51-231-a453155e`. Сохранены cutover/promote scripts, overrides, restore logs и rollback metadata. Для уже обновившихся клиентов использовать только совместимый recovery `magicmusiccrm-server:230-recovery-231-8a966d97d05d`, ID `sha256:dd59b74f776d1c27acc32f6bb6517c283c980b4251a1cdc6ebb6a03d047a2471` (base eb2575d3 + пять backports из manifest). Vanilla 230 не понимает новый preview-контракт. `rollback-manifests/restore-230.sh` проверен синтаксически; в рабочем production не запускался. При rollback не восстанавливать backup поверх живой истории и не применять down migrations.

Локальная диагностика: `dist/deploy-231`: preflight, backup metadata, restore-pre/post, cutover, promote, public-artifacts, github-release, final-production-state. Соответствующие серверные логи сохранены в release directory. Основные исходники/артефакты не изменялись после сборки.

Ручная приёмка на реальных учётных записях заказчика после deploy не выполнялась; реальные платежи, письма и тестовые финансовые записи не создавались. Выпуск не расширяет границы UI/платформенного покрытия кандидата. Windows Setup без Authenticode; публикация AAB здесь означает файл в downloads/GitHub, не Google Play submission. Следующий пользовательский шаг — обновиться до 231 и открыть исправленную форму занятия.
