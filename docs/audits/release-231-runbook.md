# Release 231: порядок выпуска

Статус сборки и фактические результаты: [release-231-candidate.md](release-231-candidate.md). Этот документ не является разрешением на deploy. Production в ходе подготовки не изменялся.

## Обязательные границы

Клиент `1.5.51+231` требует API, понимающий `includeSuggestions` в preview занятия. Сначала API, затем клиентские каналы. Vanilla 230 не является совместимым rollback для уже обновившихся клиентов. Резервный образ строится из production source `eb2575d30f24472c5500bb921dddc30b659a2286` с пятью явными backports; его manifest перечисляет реальные hashes. Он сохраняет новый контракт и изоляцию получателей уведомлений. При аварийном возврате допускается прежний состав оперативной ленты занятий; финансовая и audit-история не откатываются.

Ожидаемая схема — `0161_restore_notification_preferences`; новых миграций относительно 230 нет. Локальная проверка выполнена на PostgreSQL 17. Реальная версия production PostgreSQL и актуальные image ID, схема и ограничения должны быть прочитаны непосредственно перед deploy; старый handoff не заменяет это чтение.

## Последовательность после прямой команды владельца

1. Прочитать актуальные AGENTS, release evidence и metadata кандидата. Сверить публичные `latest.json` / `latest-v2.json`, Git tag и production image ID с зафиксированной основой. Если build 231 уже занят или production изменён — остановить только публикацию и согласовать новую версию/основу; не перезаписывать чужой выпуск. Скопировать артефакты и candidate/recovery images в отдельный release directory, сверить SHA-256 до переключения.
2. Создать свежий encrypted production backup штатным механизмом, сохранить копию вне сервера и проверить хеш. Запустить `infra/scripts/verify-release-backup-compatibility.sh` для точных candidate и recovery image ID на этом backup, с текущей версией PostgreSQL и схемой 0161. Изолированная синтетическая проверка из подготовки не заменяет этот шаг. Не применять down-migrations и не восстанавливать backup поверх живой истории.
3. Прочитать реальный DB contract (table/trigger/constraint/function hashes), подготовить candidate/rollback compose overrides. Запустить существующий `infra/scripts/deploy-api-release.sh` с точными image/revision/version, `--expected-current-image-id` фактически работающего 230 и проверенным recovery image в rollback-параметрах. Не использовать значения contract из примера help без сверки. Требовать `DEPLOY_API_RELEASE|PASS`, healthy/live/ready, отсутствие новых рестартов, outbox/reconciliation без расхождений.
4. Только после серверной приёмки опубликовать Setup/ZIP/APK/AAB, release history, immutable Git tag/release и оба update manifest. Имена, размеры и SHA-256 брать из созданного `artifact-manifest.json`, не пересчитывать по иной локальной сборке. QA APK с loopback API и тестовым профилем в клиентские каналы не включать. Проверить публичные URL, скачанный ZIP/APK и согласованность обоих каналов.
5. Выполнить post-deploy reconciliation, проверить чтение и доступность критичных путей разрешёнными тестовыми учётными записями без реальных платежей/писем. Снять свежий послеоперационный encrypted backup и сохранить evidence. При серверной ошибке использовать проверенный recovery image; metadata каналов восстанавливать из сохранённых копий. Не исправлять расхождения ручным удалением финансовых или учебных фактов.

## Артефакты локальной подготовки

Рабочая копия: `C:/Users/Alinka/.codex/worktrees/release-st-completion/MagicMusicCRM`.

Релизный каталог — `dist/release-231`; диагностический — `dist/rc231`; native/API evidence — `dist/http-journeys/<runId>`. Наличие этих каталогов само по себе не означает PASS: ориентироваться на итоговый статус кандидата и manifest. Скрипты сборки/проверки в `dist/rc231` создают только локальные артефакты и временные БД на loopback PostgreSQL 54357.
