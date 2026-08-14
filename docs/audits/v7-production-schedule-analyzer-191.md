# Production Schedule Analyzer rollout `1.5.11+191`

Дата: `2026-08-14` (МСК)

Результат: **PASS**

## Зафиксированный кандидат

- Feature/release commits: `2fa4d4f6`, `f1769144`, `a9fbf70c`, `bcb26f36`.
- Release revision и tag `v1.5.11`:
  `bcb26f36d408e0ddd94d31bec71670ff4184fdad`.
- Image: `magicmusiccrm-server:1.5.11-191-bcb26f36`.
- Image ID:
  `sha256:3e07755c5024e118e7029bf1a8a7bf79dd9e0ec95beaf99326d7278110df080d`.
- Transport archive: `82 777 088` bytes, SHA-256
  `C28F98B10BF4D5F947FF6ABDFC66F36A539657CCC9FF89DD40448232FDA969A9`.
- GitHub Release: <https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.11>.

## Изменение

- Постоянные планы и одиночные занятия используют единый Schedule Analyzer.
- Анализатор проверяет преподавателя, аудиторию, ученика, группу и филиал,
  группирует одинаковые конфликты и ранжирует варианты решения.
- Для конфликта предлагаются свободные аудитории в то же время, ближайшее
  свободное время, преподаватели той же специализации и комбинированные
  варианты.
- Conflict Inspector встроен в формы плана и одиночного занятия до сохранения.
- Старый отдельный редактор предпочтений удалён из пользовательского сценария;
  «План постоянного расписания» сохранён и доработан.
- Миграция `0137_lesson_resource_bookings` материализует бронирования ресурсов и
  добавляет PostgreSQL exclusion constraint от пересечений teacher/room/student/
  group. Запись в таблицу разрешена только триггерам; runtime-роль имеет SELECT,
  но не DML.

## Release gates

- Flutter: `805/805`, `flutter analyze` PASS.
- Backend: `185/185` suites, `1452/1452` tests; typecheck/build PASS.
- Добавлен отдельный unit-test preview одиночного занятия через общий analyzer.
- Production-like gate: migration `0137`, live/ready и reconciliation PASS.
- Exact image: invalid config fail-closed, healthy readiness и degraded `503`
  PASS.
- Strict security preflight: `11 PASS / 0 WARN / 0 FAIL`.
- Semgrep: `210` rules по `23` изменённым TS/Dart-файлам, `0` findings.
- Gitleaks по четырём release commits: `0` leaks.
- Trivy exact image: `0` High/Critical vulnerabilities, `0` secrets.
- Windows portable и Setup install/launch/uninstall PASS.
- APK: `versionName=1.5.11`, `versionCode=191`, Signature Scheme v2 PASS,
  certificate SHA-256
  `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
- APK update/cold launch на Android API 35 и AAB signature PASS.

## Backup и rollback

- До mutation создан encrypted backup
  `magicmusiccrm-staging-20260814T191342Z.tgz.enc`, `133 696` bytes,
  SHA-256
  `371C56DD1D3CE82C7CC19FC7536DA051B6E20DD8867DF73F510E43E8AFECD50C`.
- До cutover backup полностью восстановлен в изолированную БД; counts,
  миграция `0137`, reconciliation, candidate readiness и совместимость
  предыдущего image проверены.
- После rollout создан encrypted backup
  `magicmusiccrm-staging-20260814T195627Z.tgz.enc`, `134 960` bytes,
  SHA-256
  `C78F3C63E78CA7EE297303EDB2C2968C63817B96913E2CF4AC10F9EA247858DB`.
- Post-deploy backup скопирован off-host, расшифрован и полностью восстановлен:
  все внутренние SHA-256 PASS, migration `0137`, counts стабильны,
  reconciliation `issues=[]`, candidate и rollback image готовы.
- Предыдущий image сохранён как
  `magicmusiccrm-server:rollback-pre-schedule-analyzer-20260814T1945Z`.
- Старые manifests сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260814T1947Z-pre-191`.

## Cutover

- Первая попытка безопасно откатилась на точный предыдущий image: deploy-only
  проверка ошибочно ожидала отсутствие любых `NOT VALID` constraints во всей
  БД, хотя в `app.messages` уже существовали три известные ограничения.
- Проверка была сужена: глобальный baseline остался `3`, а для новой таблицы
  `lesson_resource_bookings` требуется `0` невалидированных constraints.
- Повторный cutover PASS; production API работает на exact candidate image.
- Два `502` были только health-probe запросами в первые две секунды запуска
  нового контейнера. После 60-секундного startup-окна HTTP 5xx: `0`.

## Production verification

- Runtime revision/version: `bcb26f36` / `1.5.11+191`.
- Migration head: `0137_lesson_resource_bookings`.
- API health `healthy`, restart count `0`, fatal/unhandled runtime signals `0`.
- Все шесть обязательных production worker flags равны `true`.
- Двойной post-deploy reconciliation: `issues=[]` / `issues=[]`.
- PostgreSQL: booking constraints `1`, sync triggers `2`, invalid booking
  constraints/indexes `0`, app privileges `SELECT=true / DML=false`.
- В текущей очищенной production БД активных scheduled lessons и resource
  bookings `0`; защита проверена миграционными и PostgreSQL integration tests.
- Outbox pending/dead, stale exports, analytics failures, lesson/task/installment
  poison и новые exhausted email deliveries: `0`.
- Сохраняется один исторический exhausted email от `2026-08-13`; новых ошибок
  доставки во время rollout нет. Историческая запись не удалялась.
- Оба update manifests идентичны, указывают build `191` и точный Windows ZIP
  SHA-256. Четыре public URL вернули ожидаемые размеры; Windows ZIP повторно
  скачан с production-домена и совпал по SHA-256.
- GitHub Release опубликован как ready; GitHub-computed digests и размеры всех
  четырёх assets совпали с release-кандидатом.

## Клиентские артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 543 720` | `D4E473C71863E63B465C39705BF2492BC804A61875E2C7784FCC0A3EB20E9A04` |
| Windows Setup | `15 385 437` | `A67E3503EA2EE9EB1D54466F423FB69490C36A1B2390F3E5B54653C42D362FF3` |
| Android APK | `86 279 561` | `82F6C8F499DE8C49AF5AD3683CC521763940DE710A35C6B4876C419AE6AF434F` |
| Android AAB | `60 643 886` | `D99E76B0B99AD8E41F82161A6B61A9EA9380E188DD670B036DAC66C24540731A` |

Технический rollout завершён. Предметная owner-UAT на реальных занятиях
остаётся отдельной проверкой: production сейчас не содержит активного
расписания, поэтому реальные конфликтные сценарии не создавались.
