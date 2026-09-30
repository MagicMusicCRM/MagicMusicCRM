# Production 1.5.52+232 — опубликован 30.09.2026

Владелец разрешил коммит и выпуск текущего production 231 вместе с UI-изменениями этой задачи. Режим списка воронки исключён. Исходная рабочая копия не изменяется: кандидат собран в `codex/ui-release-232` от тега `v1.5.51` (`a453155ea89ef366ff1bc3f2cec27941897a7549`).

## Состав

Равномерные поля и дополнительные сведения ученика; постоянные действия форм; компактный каталог персонала с фильтрами и последовательной карточкой; защита черновиков; обычная запись на занятие из карточки ученика. Таблицы финансов с переключателем поступлений/расходов, состояния задач и воронки, фильтры и конфликты расписания, поиск всей доступной истории открытого чата/канала.

Сохранены новые возможности 231: персональные права, история действий персонала, загрузка полной карточки с защитой от устаревших ответов, доступность преподавателя, версии финансовых команд, расчёты и уведомления. График открывается в существующем редакторе. Новых миграций и зависимостей нет.

Продуктовый commit: `0d859b4eea335cfdfaa9f561502cd5d591360f57`. Регистрация E2E в runner: `b765c996d` (не меняет приложение или сервер). Исправления геометрии и закрепления действий: `37122f0f24a545f421cb1c71d51a0d8b6e7b56d4` — исправление desktop геометрии. Финальный исходник клиента: `8653d650b76e28531d7df261edbb7c52fea76397` (восстановлена связь прокрутки мобильной формы с draggable sheet). Сервер не менялся после `0d859b4ee`.

## Проверки

| Область | Наблюдаемый результат |
|---|---|
| Flutter | Полный прогон `37122f0f2`: **1880 PASS / 3 FAIL / 4 штатных skip**, `dist/release232/flutter-release-final.log`. Три ошибки редактора закрыты в `8653d650b`: **57 PASS** в затронутых suites (мобильные жесты, закреплённые действия, подтверждение потери черновика), `mobile-form-final.log`. Это full с адресным закрытием, не новый зелёный full. **0 issues** в финальном `analyze-release-final.log`. Четыре изолированных updater audit ранее прошли на `0d859b4ee` в общем прогоне **1887 PASS**, `flutter-final.log`; код updater после этого не менялся. |
| Backend | Full `f6847ed279b512f6`: **4164 PASS / 2 timeout** из 4166 в 324 suites, 0 skips. Обе миграционные проверки повторены без конкурентной нагрузки: `07b920cd0cfb3c35`, **2 PASS** за 16.6 с. Исходник тестов и timeout не менялись. Source SHA-256 `16eb6d7b0b39d1162882f05eea5f9da075ba297932375224f3781e42f4edd6e0`. Это полный прогон с адресным закрытием двух сбоев, не заново запущенный зелёный full. Typecheck/build PASS. |
| Готовый образ | **PASS**: invalid configuration fail-closed, live/ready и healthcheck, degraded readiness HTTP 503; изолированные БД/контейнеры очищены. `dist/release232/image-gate.log`. |
| Native UI / HTTP / restore | **26 PASS**, 0 fail, 43 HTTP requests, 0 server errors. Run `3f2f2ee4ac864c038b1a3ad36adfa7b0`, source `37122f0f2` (границы финальной поправки ниже). Включает все **18 UI сценариев**, employee persistence/failure recovery и restore 142 таблиц. [Сохранённый результат](release-232-evidence/ui-http-result.json). |
| Упаковка | Windows Release build / первый кадр / 5 секунд без сбоя **PASS**. Setup и ZIP; все 27 runtime-файлов ZIP побайтно совпадают. Production APK/AAB **PASS**, versionCode 232, штатный сертификат SHA-256 `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`. APK установлен на собственный QA emulator, экран входа проверен offline, crash log пуст. [Артефакты](release-232-evidence/artifact-manifest.json). |
| Production backup | Свежий encrypted архив `magicmusiccrm-staging-20260930T184719Z.tgz.enc`, SHA-256 `6d4d5650535f82c4cc3c0c90f4f83af080185c90a741595973762baa366585f2`. Скопирован в `C:/Users/Alinka/Documents/MagicMusicCRM Backups/release-232`, хеш совпал. Изолированное восстановление на candidate и rollback **PASS**, PostgreSQL 16.4, схема 0161. |

Команды: `flutter test --no-pub --reporter expanded`; `flutter analyze --no-pub`; `npm --prefix server run typecheck`; `npm --prefix server run build`; `npm --prefix server run test:full`; адресный повтор `npm --prefix server test -- --runTestsByPath src/crm/branch-lifecycle-migration.spec.ts src/platform/organization-outbox-requeue-migration.spec.ts`. E2E: `node scripts/http-journey-check.cjs --audit-ui-usability --release-journeys`, только synthetic loopback-данные.

При переносе устранены реальные дефекты: слишком высокая desktop-карточка при масштабе 125%, конфликт PageStorage между раскрытым разделом персонала и прокруткой поля, ненужный setState при восстановлении раскрытия. Существующие проверки актуализированы для раскрытия доступа и выбора расходов. Проверка API trace сравнивает eager-чтения: разные высоты routed/modal представлений закономерно монтируют lazy-разделы в разный момент.

## Сборка образа и откат

Candidate `magicmusiccrm-server:1.5.52-232-candidate`, ID `sha256:111d8d047415179462e8da5176e3fab01c9378c957aad4f54013b5837cab6e36`, OCI revision `0d859b4eea335cfdfaa9f561502cd5d591360f57`. Образ использует проверенный runtime 231 и свежий `server/dist`; `package.json`, lockfile, Dockerfile и миграции идентичны 231. Рецепт: `dist/release232/image-context/Dockerfile`; compile: `server-build.log`. Две исходные сборки остановлены на медленном `npm prune`; повторная установка неизменённых runtime-зависимостей не потребовалась.

Rollback API: `magicmusiccrm-server:1.5.51-231-candidate`, ID `sha256:17e9e0e7a192278c7ee87fc0f231479062ec93eb9187a3259f41969b7fab9a39`, revision `b001956361b9b8c237af6b119bc06dbb23d71400`. Сохранены оба update-манифеста и история 231. Скрипты — `/opt/magicmusiccrm/releases/1.5.52-232`, `cutover.sh`, `rollback.override.yml`, `rollback-manifests/restore-231.sh`. Откат не восстанавливает старую production-БД и не переписывает историю. При возврате API 231 новый поиск истории в уже установленном клиенте 232 будет показывать ошибку; обычная переписка использует прежний контракт. Публикация каналов 231 возвращает прежний клиентский выпуск.

Первый локальный E2E запуск выявил ошибки подготовки: не добавлен allowlist нового сценария; затем pg_dump 17/pg_restore 17 использовались с локальным PostgreSQL 16.4 (`transaction_timeout`). Allowlist исправлен отдельным commit; synthetic E2E выполняется на локальном PostgreSQL 17. Production restore отдельно проверен штатными контейнерными инструментами PostgreSQL 16.4. Эти неуспешные прогоны не объявляются PASS.

Повторный native прогон обнаружил разную высоту input-контейнеров и внешний scroll окна занятия, уводивший действия за край. Общая InputDecoration теперь сохраняет 48 px независимо от иконки, `showLessonEditorSurface` оставляет прокрутку полей внутри `MagicFormBody`. Для сохранения первой строки занятий при 125% убрана лишняя рамка вокруг компактной заметки и уменьшены внешние отступы профиля. 67 профильных проверок PASS, затем все 18 native UI сценариев PASS; более ранний run `ecd156910f994fb4930966ae355a4a8c` (25 PASS/1 FAIL с тремя UI ошибками) не используется как положительное свидетельство.

Финальная поправка мобильного поведения: передача sheet ScrollController через PrimaryScrollController в MagicFormBody. Существующая проверка dirty swipe сначала воспроизвела ошибку (`mobile-handle-red.log`), затем прошла вместе с 56 другими (`mobile-form-final.log`). Две прежние проверки внешней прокрутки обновлены под фактический контракт формы с внутренней прокруткой и проверкой видимости панели действий. Промежуточный запуск содержал ошибочный путь несуществующего теста `magic_sheet_test.dart`; повтор использует реальные suites `expandable_magic_sheet_test.dart`, `magic_modal_layout_test.dart`, `adaptive_surface_policy_test.dart`.

## Фактический выпуск

30.09.2026, 22:24 Europe/Moscow: canonical deploy выполнил переключение API, проверил readiness/schema/DB contract/reconciliation и открыл публичный трафик. Оба update-канала и release-history переключены на 232; все четыре файла доступны с правильными размерами, публичный ZIP скачан и проверен по SHA-256. API healthy/restart 0, outbox pending/deadLetter 0/0, reconciliation `issues=[]`. [Публичная проверка](release-232-evidence/public-publication.json), [готовность](release-232-evidence/public-readiness.json).

Клиентский source/tag: `8653d650b76e28531d7df261edbb7c52fea76397` / `v1.5.52`. Серверный source: `0d859b4eea335cfdfaa9f561502cd5d591360f57`; `git diff 0d859b4ee 8653d650b -- server` пуст. [GitHub Release](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.52) содержит четыре артефакта с совпадающими digest/размерами; [проверка GitHub](release-232-evidence/github-release.json).

Post backup: `magicmusiccrm-staging-20260930T192438Z.tgz.enc`, SHA-256 `271b3755559d4652430491426fce0511c4b89b5f74fd7b93ac0402e5d6090afd`. Скопирован вне сервера в ту же папку release-232, хеш совпал. Восстановление на candidate и rollback 231 **PASS**, schema 0161. [Журнал публикации и восстановления](release-232-evidence/production-publish-post.txt).

Первая Android-сборка с `--no-pub` остановилась из-за оставшегося после native E2E `IntegrationTestPlugin` в generated registrant. Штатные `flutter build apk --release --target=lib/main.dart` и `flutter build appbundle --release --target=lib/main.dart` пересоздали служебные файлы и прошли. Зависимости и исходник приложения не менялись.

Native UI/HTTP run фиксирует `37122f0f2`; финальная разница клиента `8653d650b` — только передача контроллера мобильной панели и существующие проверки. Она проверена 57 адресными сценариями, анализом и собранными Windows/Android Release; native run не выдаётся за повторённый на последнем SHA. Ручная приёмка с реальными учётными записями владельца не выполнялась.

Условия повторения E2E: PostgreSQL 17 на loopback, synthetic owner/app роли `magiccrm_owner` / `magiccrm_app`; `HTTP_JOURNEY_ADMIN_URL` указывает только на локальный postgres; `HTTP_JOURNEY_IMAGE=magicmusiccrm-server:1.5.52-232-candidate`. Команда `node scripts/http-journey-check.cjs --audit-ui-usability --release-journeys` создаёт отдельную synthetic БД и удаляет её после завершения. Для desktop нужен Windows Flutter toolchain; SDK Firebase C++ берётся из штатного Flutter build cache. Production backup проверялся отдельно штатным PostgreSQL 16.4, не локальным 17.
