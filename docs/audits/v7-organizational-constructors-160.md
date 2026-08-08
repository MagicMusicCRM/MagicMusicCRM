# V7 — организационные конструкторы и доступ существующих записей

Дата инженерной проверки: 2026-08-08
Кандидат: `1.5.1+160`

## Результат

- Новый сотрудник создаётся одной атомарной операцией как пользователь,
  профиль, CRM-сотрудник, филиальные назначения и связь user↔staff.
- Новый преподаватель создаётся тем же способом с фиксированной access-role
  `teacher`, обязательными филиалом и дисциплиной из доступных справочников.
- Для существующего сотрудника или преподавателя без входа доступна команда
  «Создать доступ»: она назначает обязательные email/пароль существующей записи,
  а не создаёт второй CRM-профиль. Повторная или конфликтная привязка запрещена.
- Группа требует действующий филиал, назначенного в него преподавателя и
  аудиторию этого филиала. Завершённое назначение преподавателя не считается
  активным; явное повторное назначение корректно открывает его снова.
- Аудитории создаются и редактируются внутри карточки филиала. Отдельный
  конструктор аудиторий и legacy inline-варианты custom fields удалены.

## Проверки

| Барьер | Результат |
|---|---:|
| Backend typecheck/build | PASS |
| Backend full suites | 157/157 |
| Backend full tests | 1246/1246 |
| PostgreSQL account/legacy provisioning | PASS |
| Flutter analyze | PASS |
| Flutter full tests | 649/649 |
| V4 inventory | routes 320, DTO fields 801, unowned 0 |
| V6 route/surface inventory | routes 22, reachable 260, unowned 0 |
| V6 wire inventory | 277/277 production calls owned |
| V7 commerce/schedule inventory | finance 256, lesson mutations 7, unowned 0 |

## Release-артефакты

| Файл | SHA-256 |
|---|---|
| `MagicMusicCRM-1.5.1-160-windows-x64.zip` | `D19417028D7777D5DBBB79A6C67250F9E59BE04CD09D7A601C25994608ACCC2D` |
| `MagicMusicCRM-1.5.1-160-Setup.exe` | `4EADC87EF894F0F804C1145DA9F2DD25A88D615AEB032F1DDDA8891CE76793A8` |
| `MagicMusicCRM-1.5.1-160.apk` | `3F935D5AEF0FA9D99F1D457CC5397B693085D403654C6EFDEA72EF18ED83B30F` |
| `MagicMusicCRM-1.5.1-160.aab` | `E5EE8C841C1F19DBDD49CF895B7BED00A98D1A17EB676A54DC4473FDCAAFD40F` |

APK: release certificate `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`,
APK Signature Scheme v2 PASS, `versionName=1.5.1`, `versionCode=160`. AAB JAR
signature PASS. Windows ZIP содержит executable и `data/app.so`.

## Production

Production deploy и Windows Release UI/API/DB retest фиксируются отдельным
дополнением после backup, health-check и rollback-ready обновления сервера.
