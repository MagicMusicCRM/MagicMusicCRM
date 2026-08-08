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
| Backend full tests | 1247/1247 |
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
| `MagicMusicCRM-1.5.1-160-windows-x64.zip` | `6BFBDF8A929520D3DF3E2600B108C44187184666C480891CD629592F088A5C67` |
| `MagicMusicCRM-1.5.1-160-Setup.exe` | `073DEEA40BD0DC35C7F0E9912DD2ACEF0991D6DB994F43A1BAB4CD57A6A96A4F` |
| `MagicMusicCRM-1.5.1-160.apk` | `8A2F014775E880C86947374A14B5E736B38B01F98D2DD74786089BFA513E6665` |
| `MagicMusicCRM-1.5.1-160.aab` | `FD90FD1FBC7C257A65234BA7C63C19386865B868A3BDAC1A8FE13FBE1606CB58` |

APK: release certificate `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`,
APK Signature Scheme v2 PASS, `versionName=1.5.1`, `versionCode=160`. AAB JAR
signature PASS. Windows ZIP содержит executable и `data/app.so`.

Windows Release-проверка обнаружила и до публикации закрыла смешение ролей:
старому Staff больше не предлагается `teacher`; UI выбирает `admin`, а backend
отклоняет такой прямой запрос до вычисления hash и обращения к БД. Скриншоты
финального UI находятся в `v7-organizational-constructors-160-evidence/`.

## Production

- Перед изменением создан и проверен PostgreSQL backup
  `/opt/magicmusiccrm/backups/manual/magiccrm-pre-6ad5b50-20260808T185000Z.dump`,
  SHA-256 `28fc94c425ff2f5b441f9e3e6bbcc47f7a331d2100aa9ceeada18acaa6ecb39d`.
- Production API развёрнут из `ebcd7fa`; `/opt/magicmusiccrm/DEPLOYED_REVISION`
  и image tag совпадают, публичный health-check проходит.
- Реальный legacy Staff проверен прямым запрещённым запросом `role=teacher`:
  API вернул 403, повторное чтение подтвердило `isAppAccount=false` без
  изменения email или создания связи.
- Rollback images `8792f23`, `pre-6ad5b50` и `pre-ebcd7fa` сохранены.
- `latest.json` и `latest-v2.json` атомарно опубликованы с
  `version=1.5.1+160`, `buildNumber=160` и SHA Windows ZIP из таблицы выше.
  Публичные ZIP/Setup/APK/AAB отвечают 200 с точными размерами; удалённые
  SHA-256 повторно совпали с локальными.
- Windows Release проверен на production-данных без сохранения формы:
  [список сотрудников](v7-organizational-constructors-160-evidence/release160-staff.png),
  [старая запись без аккаунта](v7-organizational-constructors-160-evidence/release160-legacy-staff-access.png),
  [финальная форма выдачи доступа](v7-organizational-constructors-160-evidence/release160-provision-access-form.png).
