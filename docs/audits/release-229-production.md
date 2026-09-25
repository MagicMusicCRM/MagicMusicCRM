# Release 1.5.49+229 — 25.09.2026 (Europe/Moscow)

Статус: **клиентский выпуск опубликован, production-проверка пройдена**. Владелец прямо поручил выпустить его в production.

## Состав

- Source commit/tag: `685f5df529f3bb811849e3fd4c60ba93c173cf87` / `v1.5.49`.
- GitHub Release: https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.49.
- Расписание переключается между «По аудиториям» и «По преподавателям». У преподавателя неделя и день показывают его занятия и серые занятые периоды на вертикальной шкале часов; заблокированное время нельзя выбрать для создания занятия. Вид по аудиториям сохранён.
- Серверный код между `v1.5.48` и этим коммитом не менялся. API image остался `sha256:a1312c700e0538f412ec97d7dae9e55378535f654ae54419516efc9c4cc33665`, миграция — `0161_restore_notification_preferences`.

## Проверки кандидата

1. Flutter: полный прогон **1879 PASS, 4 штатных skip, 0 FAIL**. После синтаксической правки финального коммита адресный прогон **35 PASS**, анализатор: **0 errors, 0 warnings**, 30 существующих info. Логи: `dist/release229/flutter-full-final.log`, `flutter-analyze-final.log`.
2. Backend: `npm ci`, typecheck и build PASS; полный набор **324 suites, 4164 tests PASS**, очистка временной БД завершена. Evidence: `server/coverage/test-runs/5773b213443cabc5/summary.json`.
3. Production-like gate: **24 PASS, 0 FAIL**, 43 HTTP-запроса, 0 server errors. Включены реальное сохранение из UI, отказоустойчивость и изолированное восстановление backup. Evidence: `dist/http-journeys/6adc2ba3679f427da73bf4c357b20112/result.json`.
4. Windows ZIP и Setup собраны из финального коммита; ZIP содержит 31 файл, исполняемый файл показывает `1.5.49+229`, запуск из распакованного ZIP прошёл. APK/AAB собраны штатным Flutter release pipeline. APK `versionCode=229`, `versionName=1.5.49`, подпись совпадает с предыдущим релизом; AAB `jar verified`.

## Публикация и сверка

- Точный source commit опубликован в ветке `codex/schedule-teacher-tabs-230` и теге `v1.5.49`. GitHub Release содержит Windows Setup/ZIP и Android APK/AAB; размеры и SHA-256 совпали с локальными файлами.
- До переключения оба канала и история показывали build 228, API image совпал с ожидаемым, readiness был `ok`, outbox `0/0`, reconciliation `issues=[]`.
- Перед переключением создан encrypted backup `magicmusiccrm-staging-20260925T012506Z.tgz.enc`, SHA-256 `23B4B42DC9039893769732A9EF24F3BD4A16E7D15D5A679D6DAD4E25EE4A1301`. После переключения создан `magicmusiccrm-staging-20260925T012801Z.tgz.enc`, SHA-256 `E0C19C88F3B333D5064FBA8F65F35BFA2F778F23E226959FA60F46673CBAD968`. Оба скопированы вне сервера и восстановлены в изоляции на текущем и резервном API-образах с миграцией 0161 — PASS.
- На сервере все 4 пакета и 3 файла метаданных прошли SHA-256. Атомарное переключение двух манифестов и истории вернуло `PROMOTE_MANIFESTS|PASS|build=229|channels=2|artifacts=4`.
- После публикации оба публичных манифеста и история показывают build 229; все 4 URL отвечают 200 с ожидаемыми размерами. Тело публичного Windows ZIP совпало по SHA-256 `FC6904251D96E11EA8068F47B623BC675DA4E5D8CF3EE7822080F7ADA43C2AFE`. Readiness `ok`, схема 0161, outbox `0/0`, reconciliation `issues=[]`, API image не изменился.

## Откат и граница проверки

- Снимки метаданных build 228 и проверенный `restore-228.sh` находятся в `/opt/magicmusiccrm/releases/1.5.49-229-685f5df5/rollback-manifests`. При ошибке можно вернуть оба канала и историю на build 228. Уже обновлённые клиенты требуют исправления новым build; живую историю занятий, оплат и audit не откатывать.
- Автоматические проверки подтверждают названные сценарии и доступность пакетов. Ручная визуальная приёмка с реальными ролями и данными заказчика не выполнялась и не считается подтверждённой.
