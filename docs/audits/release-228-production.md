# Release 1.5.48+228 — 25.09.2026 (Europe/Moscow)

Статус: **production-выпуск завершён; полная пользовательская приёмка не заявлена**.
Владелец поручил выпустить готовый кандидат вместе с ожидающими обновлениями.
Кнопка «Добавить лид» не входит в этот выпуск по прямому решению владельца.

## Состав и идентичность

- Source/tag: `c4dde126bc7f37252110d252b97d8ca6c608c9c1` / `v1.5.48`.
  Заморожены 2207 tracked source-файлов, SHA-256 отпечаток
  `509558b6a598b93ef3e5e71097ad2231ead70dab6a63a2aa7f68dacc71942ce5`.
- В выпуск вошли уведомления в общем заголовке, адресация уведомлений,
  карточки Staff/Teacher на одной странице, переходы из поиска, разовая и
  еженедельная занятость преподавателя. Миграция
  `0161_restore_notification_preferences`.
- API image `magicmusiccrm-server:1.5.48-228-final`, ID
  `sha256:a1312c700e0538f412ec97d7dae9e55378535f654ae54419516efc9c4cc33665`.
  Release directory: `/opt/magicmusiccrm/releases/1.5.48-228-c4dde126`.
- [GitHub Release v1.5.48](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.48)
  опубликован с четырьмя файлами; APK/AAB на Google Play не публиковались.

## Проверки точного кандидата

1. Backend: **324/324 suites, 4164/4164 tests PASS, 0 skips**; typecheck и
   build PASS. `server/coverage/test-runs/a6a16728a0888522/jest-results.json`.
2. Flutter: **1878 PASS, 4 штатных skip, 0 FAIL**; анализ `lib` без замечаний.
   `dist/release228/flutter-full-c4dde126.jsonl`. Адресный сценарий занятости
   по датам прошёл после обновления теста для нового диалога.
3. Production-like Windows UI/HTTP/PostgreSQL/restore: **24 PASS, 0 FAIL**,
   43 HTTP-запроса, 0 server errors.
   `dist/http-journeys/16dbb15ab9004e6ea688123b13a28f8b/result.json`.
4. Windows ZIP проверен по всем 31 файлам; Setup собран, ZIP launch smoke — PASS.
   Android APK подписан прежним release-сертификатом
   `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`,
   versionCode 228; AAB signature и встроенная история версии — PASS.
   APK install/launch на API35 emulator — PASS. Это smoke, не authenticated UAT.
5. Полная проверка локальных пакетов и повторное скачивание всех четырёх
   публичных HTTPS-файлов по размеру/SHA-256 — PASS. Оба update-канала,
   публичная история и readiness — PASS. `dist/release228/artifact-manifest.json`,
   `dist/release228/public-verification.json`.

| Публичный пакет | SHA-256 |
| --- | --- |
| Windows Setup | `2ec094257539f46b303c9199893e7df8771578be5b656d7149788fd1b2944dc1` |
| Windows ZIP | `95d0a2d17249deba481d0e2b835a4fe96590d249713f91e2d5847649febbfb39` |
| Android APK | `6f8a5a89dc7b04e3b7cdcd31c5ab94ca4ddba58bf0d8614b6d831679a0e84625` |
| Android AAB | `bdfcc614dd55b15edb55d903ed7b529dfcd319ab5fbd9b49dbc2d17d68737b7e` |

## Backup, cutover и откат

Предвыпускная зашифрованная копия
`magicmusiccrm-staging-20260924T215303Z.tgz.enc`, SHA-256
`ef461e71c02939854b1e30a3c8415cc47ad9c2a06a037418a8ca89c90519162f`,
скопирована вне сервера, hash совпал. Изолированное восстановление с точными
candidate/rollback images и миграцией 0161 — **PASS**,
`dist/release228/backup-drill-cutover.log`.

Первый drill с прежним image 227 был заблокирован: его миграционный раннер
отвергает уже применённую миграцию 0161, которой нет в образе. Подтверждённая
причина — проверка наличия SQL-файла для каждой применённой миграции.
Подготовлен совместимый резервный image с неизменным кодом API 227 и SQL 0161:
`magicmusiccrm-server:1.5.47-227-compat-228`, source
`cab9ace7b6672aad7286f911643c13003a09485f`, image ID
`sha256:b5ed356ecd02a00570b5898bc16b5ac05626231a41364e3fc14d788b95a7d5c7`.

Защищённый cutover — **PASS**. После переключения публичный readiness `ok`,
schema `0161_restore_notification_preferences`, outbox `pending=0`,
`deadLetter=0`; запущенные image/revision совпали с кандидатом. Повторная
reconciliation дала `issues=[]`. В production для `new_lead` восстановлены
настройки admin/manager/director (включено) и teacher (выключено), каналы
`in_app` и `push`. `dist/release228/cutover.log`,
`dist/release228/post-reconciliation.json`.

После выпуска создана зашифрованная копия
`magicmusiccrm-staging-20260924T215654Z.tgz.enc`, SHA-256
`ce93902124c4145152397ba4104178878ba5205121ee6b38118211a7f1c8e163`.
Она скопирована вне сервера, hash совпал; изолированное восстановление и
проверка совместимого резерва — **PASS**,
`dist/release228/backup-drill-post.log`. Для отката API использовать только
совместимый image выше и сохранённые manifest build 227 в
`/opt/magicmusiccrm/releases/1.5.48-228-c4dde126/rollback-manifests`. Схему назад не мигрировать, финансовые, учебные и
audit-факты не переписывать.

## Граница приёмки

Автоматические проверки подтверждают доставку, запуск, основные сценарии и
контракты. Доставка PUSH на устройствах всех ролей и ручная работа под реальными
ролями с сохранением/перечитыванием данных ещё не подтверждены. Для некоторых
уведомлений о занятиях и финансах переход ведёт в раздел, а не к конкретному
объекту. Поэтому выпуск не означает полной приёмки ТЗ 17.09.
