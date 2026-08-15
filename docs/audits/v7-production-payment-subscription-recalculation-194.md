# Production rollout пересчёта оплат и абонементов `1.5.14+194`

Дата: `2026-08-15` (МСК)

Результат: **PASS**

## Зафиксированный кандидат

- Feature/release commit: `7451973a`.
- Setup metadata commit, release revision и tag `v1.5.14`: `be9b19e0`.
- Server image: `magicmusiccrm-server:1.5.14-194-be9b19e0`.
- Image ID: `sha256:97f2620ba45810133f227596c8143949d7b1048a75a388173d4621affee798cf`.
- Image labels: revision `be9b19e0f3abe1f411c63f0c94243404efe3e473`,
  version `1.5.14+194`.
- Transport archive: `82 490 071` bytes, SHA-256
  `D9BE32CCBA7ED766A7211075F1A6963F447DF1BB8733D759DA36080B9CC8D1CE`.
- GitHub Release:
  <https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.14>.

## Изменение

- В карточке клиента назначенную или оплаченную запись можно изменить через
  предварительный расчёт и отдельное подтверждение.
- Исходный финансовый факт не перезаписывается. Для оплаченной записи создаётся
  равное сторно, исходная запись исключается из обычной отчётности, а новая
  версия платежа и связь коррекции добавляются атомарно.
- Пересчёт абонемента использует versioned replacement: сохраняет использованные
  занятия, переносит допустимые резервы и заранее показывает долг или переплату.
- Старый путь выдачи абонемента из лида приведён к актуальной модели: создаются
  payment record, status event, lifecycle event и aggregate versions.
- Миграция `0138_payment_record_corrections` добавляет неизменяемую связь
  исходной и заменяющей записи. Runtime-роль имеет `SELECT/INSERT`, но не
  `UPDATE/DELETE`.
- Пользовательские подписи и сообщения нового сценария русские и короткие.

## Release gates

- Flutter: `827/827`, `flutter analyze --no-pub` PASS.
- Backend: `186/186` suites, `1455/1455` tests; NestJS build PASS.
- PostgreSQL integration: correction preview/commit/replay, append-only сторно,
  projection movement и migration down/up PASS. Legacy issue path покрыт
  отдельным unit-test и полным backend suite.
- RepoWise change risk: `Elevated`, percentile `93`, review priority `high`.
  Причина: `32` файла и `2863` добавленные строки в клиенте, сервере, миграции
  и тестах. Полные suites и exact-image gate выполнены после изменений.
- Semgrep: `210` правил по `22` изменённым TS/Dart-файлам, `0` findings.
- Gitleaks по двум release commits: `0` leaks.
- Trivy filesystem и exact image: `0` High/Critical vulnerabilities,
  `0` secrets, Dockerfile misconfigurations `0`.
- Exact image: invalid production flags fail-closed, healthy readiness и
  degraded readiness `503` PASS.
- Windows portable: embedded version `1.5.14+194`, launch PASS.
- Windows Setup: Inno Setup `6.7.3`, install, version readback, launch и
  uninstall PASS.
- APK: `versionName=1.5.14`, `versionCode=194`, Signature Scheme v2 PASS,
  certificate SHA-256
  `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
- AAB JAR signature PASS; сертификат действителен до `2053-10-15`.
- Подключённого Android-устройства во время выпуска не было, поэтому отдельный
  update/cold-launch device-smoke не выполнялся.

## Backup и rollback

- До mutation создан encrypted backup
  `magicmusiccrm-staging-20260815T161726Z.tgz.enc`, `141 392` bytes,
  SHA-256
  `5237A3B2D5C09F9C92F6EEE636D898F898BD303F6B6541FC78AF42089E9DEAB2`.
- Backup скопирован off-host, полностью расшифрован и восстановлен в
  изолированный PostgreSQL. Миграция `0138` прошла `up -> down -> up`, counts
  сохранились, candidate и rollback reconciliation вернули `issues=[]`.
- После rollout создан encrypted backup
  `magicmusiccrm-staging-20260815T162831Z.tgz.enc`, `142 704` bytes,
  SHA-256
  `C57E3688815ADA80086A803D9D1639BF56388759AE1301A44840094F7596D3EC`.
- Post-deploy backup скопирован off-host и восстановлен: migration `0138`,
  counts `12/1/1/1/1/0`, candidate и rollback reconciliation PASS.
- Предыдущий image сохранён как
  `magicmusiccrm-server:rollback-pre-recalc-20260815T1625Z`.
- Manifest build `193` и прежняя release history сохранены в отдельном
  rollback-каталоге до переключения build `194`.
- После появления correction facts откат приложения выполняется на предыдущий
  совместимый image без удаления таблицы `0138`. Down migration разрешена
  только пока таблица коррекций пуста и сама блокирует потерю истории.

## Production verification

- Runtime image/revision/version: exact candidate / `be9b19e0` /
  `1.5.14+194`; restart count `0`, health `healthy`.
- Migration head: `0138_payment_record_corrections`.
- Production counts после cutover: users `12`, students `1`, subscriptions
  `1`, payments `1`, client payment records `1`, corrections `0`.
- Legacy gaps: subscription funding `0`, unlinked payment `0`, payment record
  without status event `0`.
- Две post-deploy reconciliation вернули `issues=[]` / `issues=[]`.
- Outbox pending `0`, шесть обязательных workers включены, новых fatal,
  unhandled или `Internal Server Error` в логах нет.
- `latest.json` и `latest-v2.json` указывают на `1.5.14+194`, build `194` и
  точный SHA-256 Windows ZIP. Public release history содержит `34` выпуска.
- Все четыре public URL вернули HTTP `200` и точные размеры. Windows ZIP
  повторно скачан с production-домена и совпал по SHA-256.
- GitHub-computed digests и размеры всех четырёх assets совпали с локальными и
  production-артефактами.

## Клиентские артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 569 987` | `947786620653B44C969D0982759904EABB8EDDDC696EEAB60B063A2CC76AE9DE` |
| Windows Setup | `15 403 723` | `086BA765B7E06D5E5A3663D21FEC74FD6E37FD1546776873BA107E67D98A1AEA` |
| Android APK | `86 580 024` | `C62070E910C485462778F6FC9BF604F2098227650712A1362542334EBA93E299` |
| Android AAB | `60 684 239` | `2D463B0FAB4D047177422E39C6F736BE5949CD16D8EABFB3EC2294C1C2899077` |

Production rollout завершён. Клиенты build `<194` получают золотую точку у
версии и предложение обновиться при запуске, возврате в приложение или
следующей фоновой проверке.
