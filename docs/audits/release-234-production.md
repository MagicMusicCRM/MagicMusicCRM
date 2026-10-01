# Release 1.5.54+234 — проверка исправлений

Клиентский исходник: `75d6e23722b3d287bf118e52932159eb214fea0c`.
API production остаётся 1.5.53+233, image
`sha256:533a0aba265cb16051b6b339e8645f3d0583ee297d172e49406710b03147bee8`,
source `d22915db72f477c9f1bbb89aca6204c9dd98e068`, schema
`0162_group_lesson_defaults`. Изменений сервера и миграций в этом исправлении нет.
Статус: выпущен 02.10.2026 (Europe/Moscow). Оба канала обновления и GitHub Release
показывают 1.5.54+234; Windows запущен с обычным профилем, PID 20384.
Immutable tag `v1.5.54` указывает на клиентский исходник выше.
[GitHub Release](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.54).

## Исправленные причины

1. Старые группы с пустыми типами расчёта вызывали исключение до открытия форм.
   Оба действия используют общую проверку и существующую форму настройки группы.
   После явного сохранения продолжается первоначальное действие; отмена не
   создаёт занятия или расписания. Числовая цена не превращается в тип автоматически.
2. Dart выводит `StateError` с префиксом `Bad state:`. Общий обработчик раньше
   не убирал этот префикс и скрывал безопасное русское пояснение. Теперь такие
   пояснения видны во всех вызывающих разделах; технические детали по-прежнему
   фильтруются существующей политикой.
3. После смены филиала группы редактор получал старый список филиалов и каталог.
   Он теперь использует свежий филиал, а повторное открытие настройки группы
   читает актуальную версию, чтобы не перезаписать новые значения старой карточкой.
4. Номера package/MSIX/Setup и история выпуска согласованы. Исправлено оформление
   описания предыдущего выпуска, нарушавшее существующую проверку русского текста.

## Проверяемые прогоны

Полный Flutter: `flutter test --no-pub`, 1884 PASS / 4 штатных skip.
Финальный `flutter analyze --no-pub`: замечаний нет. Запускались последовательно.
Backend не менялся: fingerprint
`3643c669d2d77ac47d6d2ad557b779a242647913d33ea94ebb99ff714d3d7538`
совпадает с полным прогоном 324 suites / 4167 PASS; полный backend повторно
не запускался. Новый HTTP/E2E прогон использует точный production image.

Десять независимых API прогонов: 390 PASS, 0 ошибок сервера. Это число включает
повторные базовые проверки. Клиенты, группы, семьи, качество данных, вход и
доставка почтовых кодов, переписка, ответственные, комментарии, напоминания задач,
экспорт зарплаты. Команды и run ID: [API evidence](release-234-evidence/api-audit-summary.json).
Условия: Docker Desktop, локальный PostgreSQL 54329, синтетические учётные записи,
`HTTP_JOURNEY_IMAGE=magicmusiccrm-server:1.5.53-233-candidate`; production не
используется как тестовая БД. Каждый audit mode запускается отдельно.

Регрессии сначала воспроизвели исходный сбой: скрытое русское пояснение,
пустые типы старой группы, смену филиала. Native выполняет реальные формы,
авторизованный HTTP и проверку сохранённых данных. Финальный исходник
`75d6e23722b3d287bf118e52932159eb214fea0c`: Native 99 контрольных шагов
(группы 13, основные формы 19, финансовый сценарий 10, расписание трёх ролей 57),
HTTP 28 + 26 + 23 PASS. Все три прогона имеют один неизменный source fingerprint.
Сводка: [Native evidence](release-234-evidence/native-summary.json).

Команды, отдельно и последовательно:

```powershell
$env:HTTP_JOURNEY_IMAGE='magicmusiccrm-server:1.5.53-233-candidate'
node scripts/http-journey-check.cjs --audit-group-plan
node scripts/http-journey-check.cjs --audit-ui-usability --release-journeys
node scripts/http-journey-check.cjs --audit-schedule-views
```

Свежие HTTP прогоны содержат 467 PASS с повторными базовыми проверками.
Проверены повтор оплаты после потери ответа, завершение/изменение/отмена занятия,
возврат средств, конфликт версий и повторное открытие сохранённой карточки.

Неуспешные промежуточные прогоны не считаются PASS. Устаревшие fixture группы
обновлены под обязательные типы; SMTP loopback корректно отображён в Docker.
Прогон с изменением метаданных во время проверки отвергнут fingerprint guard.
Два одновременных Flutter test затронули общий asset cache: повтор выполнен
последовательно. Финансовый E2E ждёт реального доступного пункта преподавателя
до выбора. Проверки не отключались, серверные данные и историю не подгоняли.

## Наблюдаемое ограничение расписания

Read-only production диагностика: из четырёх живых серий три имеют по одному
будущему кандидату с `TEACHER_UNAVAILABLE`, четвёртая уже материализована.
Это бизнес-ограничение графика, а не HTTP 500. Создание этих трёх занятий
корректно блокируется проверкой доступности; время, график и история в этом
выпуске не переписывались. Диагностика не содержит персональных данных:
[сводка](release-234-evidence/series-diagnostic-sanitized.json).

## Backup и rollback

Новый pre backup `magicmusiccrm-staging-20261001T222831Z.tgz.enc`, SHA-256
`7c53505d4a69101e501916eb7ad4322db8f2f084c16b5c73c661b07d88ced6c3`.
Внешняя копия: `C:/Users/Alinka/Documents/MagicMusicCRM Backups/release-234`.
Восстановление в изолированный PostgreSQL 16.4 и reconciliation на API 233
и recovery 232+SQL0162 PASS; production БД не менялась при restore drill.
Откат клиента возвращает оба update-канала и историю на 233 скриптом
`/opt/magicmusiccrm/releases/1.5.54-234/restore-233.sh`.
API и live DB при клиентском откате сохраняются.

Post backup `magicmusiccrm-staging-20261001T233015Z.tgz.enc`, SHA-256
`a64f8d5d9b91235c1c6e8584fd139fd1ced07acfd2cd2d019cf988baea558b5c`.
Внешняя копия в том же каталоге проверена по хешу. Post restore на API 233 и
recovery 232+SQL0162 PASS; [результат](release-234-evidence/post-backup-restore.txt).
Post reconciliation `issues=[]`, health healthy/restart 0, readiness OK,
схема 0162, outbox 0/0: [readiness](release-234-evidence/post-public-health.json).

## Файлы выпуска и запуск

Все четыре артефакта построены из git archive клиентского исходника без смены
зависимостей. Windows собран в коротком пути `C:/Users/Alinka/.codex/b234`,
поскольку вложенные пути Git/MSBuild в длинном каталоге превышали Windows limit.
Файлы опубликованы только после успешной сборки и проверки.

| Файл | Размер, байт | SHA-256 |
| --- | ---: | --- |
| Setup | 15764052 | `53c5a176bd0bb04858a2c063ce183c0433da98ccedd43ca77d038855b2ab8ba9` |
| ZIP | 19647461 | `e992cc67f5f0ea0a543c9b9cb7190ad841012e88bc62bfc1a87f312c670f36df` |
| AAB | 62496701 | `6fd297a5415dd2e63b51e9a0f3c864abd0e740821c36a45d0326d387571266fd` |
| APK | 91417834 | `b4438b64d092a0df17e95fe7f932702b0430dd1835458cc3775e61be5c0d5c00` |

Сервер проверил все четыре файла и три JSON перед продвижением. GitHub asset
size/digest совпадают для всех четырёх; оба публичных update-канала, история,
HEAD размеры и скачанные ZIP/APK хеши PASS:
[публикация](release-234-evidence/public-publication.json),
[GitHub](release-234-evidence/github-publication.json).
Медленная передача SCP заменена скачиванием этих же проверенных публичных
GitHub assets сервером; временные файлы заменялись только после совпадения хеша.

Windows Release: Native first-frame acknowledgement и 5 секунд без выхода,
изолированный профиль, PASS. Пользовательская 233 корректно закрыта; проверенный
ZIP распакован в `dist/release234/runtime`, 234 запущен с обычным профилем и
продолжает работать. Производственные записи через smoke не изменялись.
[Windows smoke](release-234-evidence/windows-release-smoke.json),
[пользовательский запуск](release-234-evidence/user-app-launch.json).

APK и AAB подписаны тем же сертификатом, что 233; APK versionCode 234,
versionName 1.5.54. APK установлен в собственный QA эмулятор без сети;
после отказа стандартному запросу разрешения уведомлений видны поля входа и
кнопка «Войти», процесс жив, crash buffer чист. Это проверка запуска, не
авторизованного Android сценария с production данными.
[подписи](release-234-evidence/android-signatures.json),
[Android smoke](release-234-evidence/android-release-smoke.json).

Повторяемые команды публикации и контроля, из каталога выпуска:

```powershell
ssh -i C:/Users/Alinka/.ssh/mmcrm_proxy_ed25519 magicdeploy@161.104.49.153 'bash /opt/magicmusiccrm/releases/1.5.54-234/promote-manifests.sh'
node dist/release234/verify-public.cjs
ssh -i C:/Users/Alinka/.ssh/mmcrm_proxy_ed25519 magicdeploy@161.104.49.153 'bash /opt/magicmusiccrm/releases/1.5.54-234/post-backup.sh && bash /opt/magicmusiccrm/releases/1.5.54-234/restore-check.sh post'
```

Promote имеет проверку неизменности API и предыдущих metadata; повторная
публикация поверх существующих файлов отвергается. Post backup уже выполнен;
команды приведены как evidence, не инструкция повторять production операции.
Гарантия отсутствия любых ошибок вне проверенных сценариев не заявляется;
ручная приёмка владельцем с реальными данными остаётся отдельным подтверждением.
