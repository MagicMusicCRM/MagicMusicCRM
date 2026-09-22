# Release 1.5.46+226 — 23.09.2026 (Europe/Moscow)

Статус: **CLIENT RELEASE DEPLOYED AND PUBLICATION VERIFIED**.
Владелец прямо разрешил выпуск и продолжение работы после паузы.
Дата подготовки кандидата в истории приложения — 22 сентября.

## Идентичность и объём

- Source commit/tag: `c9e7db1e69f09053ea6ed0b57286987c1481de46` / `v1.5.46`.
- Frozen source: 2195 файлов, SHA-256
  `f9dcd4b5a1397d58258d5c60641f6f0e0d5d28174b682efafa8f24588ddd9cdb`.
- Отдельный clean worktree: `C:/Users/Alinka/.codex/worktrees/release-226/MagicMusicCRM`.
- Между `v1.5.45` и кандидатом нет изменений в `server/`: это client-only release.
- API остаётся на `magicmusiccrm-server:1.5.44-224-final`, image
  `sha256:8954adc55c080e3398cb94f4caf6768bc9f437271c755dabd7fc090094b960a0`,
  schema `0160_requeue_lead_create_outbox`.
- Локальные артефакты и evidence: `dist/release226/`.

Включены непрерывная desktop-карточка клиента, редактируемые контакты слева,
редактор ФИО в заголовке, компактная сетка основных полей и более раннее
расположение ленты занятий. Пустые задачи занимают небольшую область, история
сначала показывает три события. Типы списания используют непрозрачные цвета;
у занятия одна рамка и одна полная подсказка, удалены дублирующие значки.
Подробные границы: [плотность карточки](client-card-density-2026-09-22.md).

## Проверки исходников

1. Полный Flutter-прогон: 1861 PASS, 4 штатных skip и одна ошибка текста release
   history (запрещённое тире). Исправлена только строка описания; повторный запуск
   release-history и release-config дал 10 PASS. Логи:
   `dist/release226/flutter-full-serial.log`, `release-metadata-followup.log`.
   Последующее изменение касается только селектора integration-теста.
2. Backend full: **323 suites / 4158 tests PASS, 0 skips**, cleanup complete.
   Run `6e37a5e4b0b9756d`, source SHA-256
   `b13478007d08668bd5ad97d15b11b48743ec1a970a555d9124edfb05deff0086`.
   Evidence: `server/coverage/test-runs/6e37a5e4b0b9756d/summary.json`.
3. Полный production-like gate на точном candidate: **24 PASS / 0 FAIL**,
   43 HTTP requests, 0 server errors; fail-closed configuration, readiness,
   reconciliation, native employee UI и synthetic restore — PASS.
   Evidence: `dist/http-journeys/731668aa09724065850018fc34f67073/result.json`,
   `dist/release226/production-like-verified.log`.
4. Native UI подтвердил оплату с потерей ответа и явным повтором без дубля,
   проведение занятия worker-ом, отмену, возврат остатка, конфликт двух карточек
   и повторное чтение сохранённого имени через редактор в заголовке.
5. Analyzer по `lib test integration_test`: 0 errors / 0 warnings, 30 имеющихся
   info-lints; exit 0. Перед сборкой release metadata: 10 PASS, updater helper:
   4 PASS (включая rollback, неверный hash и неполный пакет). Более ранние целевые
   UI/golden/device-проверки описаны в density audit и не заменяют owner UAT.

Предыдущие прерванные прогоны не считаются PASS. При одновременных тяжёлых
процессах наблюдались тайм-ауты и конфликт Flutter test assets. Финальные
проверки запускались последовательно. Неверная production-конфигурация отдельно
завершилась с ожидаемой validation error за 4,3 секунды; финальный gate тоже
подтвердил отказ запуска. Первоначальный employee UI gate нашёл устаревший
поиск отдельного текста имени вместо нового полного ФИО. Исправлен тест:
он открывает реальный редактор и проверяет точное значение сохранённого поля.

## Пакеты

Windows Setup/ZIP и подписанные APK/AAB собраны из clean candidate. Проверены
31/31 файл ZIP, неизменность frozen source, встроенная release history и подписи.
Сертификаты APK и AAB совпадают с production:
`0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
Windows Setup остаётся unsigned, как и прежние выпуски.

| Артефакт | SHA-256 |
| --- | --- |
| Windows Setup | `66b3c8fe79e408c9637e06810d8315e30bedeb3598c1659f04297c25545e8811` |
| Windows ZIP | `f120a3069603260a182c8ded2913f70e25c7a981baf4a0e52bd6397b14dadea5` |
| Android APK | `bb10bd20c3f8ed85071f575ac63bfac17fb97eecda9ce6aec5c1af91cce48808` |
| Android AAB | `ab5902dea6903f03e63214fc9934a7a248bf6db6e72bb5adfc9852da28fc6e76` |

Скачивание Firebase SDK в новом worktree остановилось без получения данных.
Через штатный `FIREBASE_CPP_SDK_DIR` использован локальный SDK той же версии
12.7.0 из предыдущей сборки. SHA-256 исходного SDK archive:
`a3ba12b7de6a88a1fd53dd9213abff10b6215e5af7e70318bc40370a07c29722`.
Зависимости и исходники приложения при этом не изменялись.

Smoke Windows: ZIP распакован отдельно, запущен именно Release EXE версии
`1.5.46+226`; окно отвечает, затем закрыто штатно. Android: подписанный APK
установлен в read-only API35 emulator, versionCode=226, versionName=1.5.46,
экран входа проверен по screenshot/UI tree, приложение остаётся запущенным,
crash buffer пуст. Это проверка запуска, не authenticated UAT.
Evidence: `windows-smoke.json`, `android-smoke.json`, `android-release-smoke.png`.

Первый Android launch check был аннулирован после визуального обнаружения
диалога System UI ANR. После остановки единственного IDLE Gradle daemon,
созданного этой сборкой, и увеличения памяти emulator с 1536 до 2048 MB
повторный запуск прошёл без системного диалога и ошибок приложения. Проверка
усилена: наличие ANR-диалога или отсутствие окна `magic.crm` теперь даёт FAIL.
Первоначальные screenshot/UI tree сохранены с суффиксом `startup-anr`, статус
первого результата заменён на `INVALIDATED_SYSTEM_UI_ANR`.

## Backup и rollback

Свежая encrypted backup:
`magicmusiccrm-staging-20260922T184222Z.tgz.enc`, SHA-256
`af1b73d5d9473424fa876853bbadd7eac96f65e0fc90e746fbff74aedeffe27e`.
Копия скачана вне production-хоста, хеш проверен, восстановление на точных
candidate/recovery images в изоляции — PASS (`backup-drill-pre/result.json`).
Живая база восстановлением не заменялась.

Совместимый server rollback:
`magicmusiccrm-server:223-recovery-0160-e4e14b6ae809`, image
`sha256:3a605547374559233590643fc68a7808a8382c68eea77e01455c6351f49bcd4e`.
В `dist/release226/rollback-manifests/` сохранены оба update-manifest и история
build 225. Их возврат остановит новые обновления, но не понизит уже установленный
226. Предпочтителен forward fix; БД и финансовую/учебную/audit-историю не откатывать.

## Публикация и ограничения

Оба update-канала и публичная история выдают build 226 / `1.5.46+226`.
Все четыре файла заново скачаны через публичный HTTPS endpoint; размеры и
SHA-256 совпали. Readiness: `status=ok`, schema 0160, outbox pending/dead-letter
`0/0`. Точный runtime image остался build 224; post-release reconciliation:
`{"backfill":null,"issues":[]}`. Живые миграции/backfill не выполнялись,
синтетические production-клиенты, задачи, занятия и платежи не создавались.

[GitHub Release v1.5.46](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.46)
опубликован не как draft/prerelease. Проверены размеры/digest четырёх assets
и точный commit аннотированного tag через GitHub API. Evidence:
`public-verification.json`, `github-verification.json`, `post-runtime.log`,
`post-reconciliation.log`, `promote-manifests.log`.

Передача APK через SCP с ПК оказалась медленной (около 100 КБ/с). Остановлен
только собственный процесс этой загрузки; каналы ещё оставались на 225.
Сервер напрямую скачал публичные APK/AAB из проверенного GitHub Release,
проверил точные SHA-256 и атомарно переименовал временные файлы. После проверки
четырёх артефактов и трёх JSON-файлов опубликованы история и оба manifest.
Первый SSH stdin script завершился ошибкой на добавленном PowerShell CR после
успешного получения APK/AAB; финальная стадия нормализовала CR и заново сверила
все семь хешей с exit 0. Незавершённый SCP `.tmp-9a4df24d1b87499cacf62e9f7a9b4bea`
не используется каналами обновления и оставлен как временное evidence.

Полная приёмка всех 20 требований не заявляется. Authenticated production UAT
нового внешнего вида выполняет владелец. Неопределённая кнопка «Добавить лид»
не добавлена автоматически: смысл действия внутри существующей карточки
остаётся отдельным продуктовым решением. Новых финансовых прав нет.
