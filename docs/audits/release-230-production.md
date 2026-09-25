# Release 1.5.50+230 — 25.09.2026 (Europe/Moscow)

Статус: **production-выпуск опубликован** по прямой команде владельца. Автоматические проверки ниже подтверждают релизный кандидат; ручная приёмка с реальными ролями и данными заказчика не проводилась.

## Состав и источник

- Source commit: `eb2575d30f24472c5500bb921dddc30b659a2286`; исправление: `331c1ac326c3e7e7a08426b89ddc635fa1c70759`.
- Tag: `v1.5.50`; [GitHub Release](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.50) опубликован, не draft и не prerelease.
- При заданных рабочих интервалах преподавателя занятие и повторяющееся расписание вне них блокируются в UI и на сервере; предварительная проверка сообщает причину. При отсутствии графика преподавателя доступны рабочие часы филиала — прямое решение владельца.
- API image: `magicmusiccrm-server:1.5.50-230-final`, ID `sha256:2f08d092013f01f7b761fc714dd5033b96619b2d01813f0080109d262725f874`. Схема осталась `0161_restore_notification_preferences`.

## Проверки кандидата

1. Полный Flutter gate: **1881 PASS, 4 штатных skip, 0 FAIL**. Адресные проверки сценариев графика и создания занятия, Flutter analyze, backend build/typecheck и updater helper пройдены.
2. Полный backend gate с физического пути проекта: **324/324 suites, 4166/4166 tests PASS, 0 skips**; временная БД удалена. Evidence: `server/coverage/test-runs/e23a5ead5a21b419/summary.json`. Предыдущий прогон через смонтированный короткий путь `M:` также дал 324/324 и 4166/4166, но обёртка сравнила пути Jest через физический `C:` с ожидаемыми `M:` и отвергла инвентарь. Повторный gate из `C:` устранил эту инфраструктурную ошибку без изменения кода.
3. Production-like gate: **24 PASS, 0 FAIL**, 43 HTTP-запроса, 0 ошибок сервера; UI-сценарий на Windows и изолированное восстановление данных пройдены. Evidence: `dist/http-journeys/f48fce55a5c647a5b95f462c37be4549/result.json`.
4. Windows Setup/ZIP и подписанные APK/AAB собраны из финального коммита. APK `versionCode=230`, `versionName=1.5.50`; APK/AAB подписаны тем же сертификатом, что предыдущий выпуск. Setup/ZIP, APK/AAB и три файла метаданных сверены по SHA-256 на сервере до публикации.

## Production-публикация и сверка

- Перед переключением создан encrypted backup `magicmusiccrm-staging-20260925T191715Z.tgz.enc`, SHA-256 `9fd657aa5348e36f09d70fd904d8737ef7764d4ba900f105bda9ec37d6ac4bae`; скопирован вне сервера. Изолированное восстановление на новом и резервном API-образах с миграцией 0161: PASS.
- Защищённый API cutover вернул `DEPLOY_API_RELEASE|PASS`; проверены точный image ID, healthy, 0 рестартов, публичный readiness `ok`, схема 0161, platform outbox pending/deadLetter `0/0` и встроенная reconciliation. Резервный образ: `magicmusiccrm-server:1.5.48-228-final`.
- Публикация двух update-каналов, истории и четырёх пакетов вернула `PROMOTE_MANIFESTS|PASS|build=230|channels=2|artifacts=4`. Публичные `latest.json` и `latest-v2.json` показывают `1.5.50+230`; первый выпуск в публичной истории — build 230.
- Все четыре публичных URL возвращают HTTP 200 и ожидаемые размеры: Setup 15 717 410 B, ZIP 19 995 109 B, APK 90 875 986 B, AAB 62 308 754 B. Публичный Windows ZIP скачан и совпал по SHA-256 `eea07bf3e21f95e5990e9d14fbe434e3e78d6cd57c20ba91ab891272f521e036`.
- GitHub Release содержит те же четыре имени и размеры. Tag указывает точно на исходный коммит. Повторная публичная readiness после публикации — `ok`, API healthy, restart 0, очередь 0/0.
- После публикации создан encrypted backup `magicmusiccrm-staging-20260925T192926Z.tgz.enc`, SHA-256 `e7baaf0730ca6c2983be24fdcae0b8f82cbe49cd9d406f306b1f1a341140818c`; скопирован вне сервера и восстановлен в изоляции на новом и резервном API-образах — PASS.

## Откат и граница проверки

- API cutover проверен с автоматическим возвратом на точный предыдущий образ. Снимки production metadata build 229 и проверенный `restore-229.sh` находятся в `/opt/magicmusiccrm/releases/1.5.50-230-eb2575d3/rollback-manifests`. Не откатывать живую историю занятий, оплат или audit.
- Автоматические результаты доказывают перечисленные сценарии и доступность пакетов. Ручная визуальная приёмка на реальных ролях и данных заказчика не выполнена и не считается подтверждённой.
