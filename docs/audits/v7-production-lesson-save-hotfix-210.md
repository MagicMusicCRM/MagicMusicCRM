# Production lesson-save hotfix — 2026-09-03

По сообщению владельца исправлен работающий сервер. Клиент остаётся
`1.5.30+210`; повторная сборка и публикация клиентских пакетов не требовались.

## Причина и исправление

Production `planned-settlement/preview` выдавал 500:
`terminal lesson reservation cannot transition`. Сохранение освобождало
резерв и выполняло UPSERT обратно в `reserved`, нарушая terminal-state guard.
Смена стандартного default ранее не исправила 14 существующих планов занятий
и один шаблон, продолжавший копировать `none`.

- Неизменное клиентское покрытие сохраняется при редактировании. После
  переключения funding повторная бронь создаёт новую запись; migration 0147
  ограничивает уникальность только активным резервом. Down migration
  останавливается при наличии истории повторных броней и ничего не удаляет.
- Плановый preview использует те же расчёт и проекцию, что фактические факты,
  без резервирования/списания. 13-е занятие при абонементе на 12 редактируется,
  сохраняя отсутствие покрытия. Фактическое завершение проверяет остаток.
  Выбор чужого либо повторного абонемента отклоняется и при нулевых units.
- Matrix/list отдают активную бронь перед исторической, включая одинаковые
  timestamps. Зелёный значок после повторной брони сохраняется.

## Кандидат

| Назначение | Revision | Image ID |
| --- | --- | --- |
| Compatible bridge | `2ce1f16fc5307aa38cd287262c980ce2464613c7` | `sha256:310db0c3682027e6c0388af7bf97a8e0fab7c861aceff783be8d3dedc8994d5f` |
| Final | `89c3c36f8f0696df771d6934c6c2f5b0ba050d9f` | `sha256:70b5263383d8d5d044931017a31c2934b99f3cb3e19dddcd7ac539d0c2983051` |

Final tag `magicmusiccrm-server:1.5.30-210-hotfix1-89c3c36f`, version
`1.5.30+210-hotfix.1`, migration `0147_lesson_reservation_history`.
Bridge tag `magicmusiccrm-server:1.5.30-210-hotfix1-bridge-2ce1f16f`.
Runtime source одинаков; final добавляет migration и регрессионные тесты.
Оба guarded cutover PASS, загруженный archive и OCI identity сверены.

## Проверки

Red tests воспроизвели production 23514, потерю reservation marker при равных
timestamps, блокировку uncovered lesson и пропуск owner/duplicate validation
при нулевом списании. После исправления 42 профильных PostgreSQL/unit tests
и 5 execution tests PASS. Проверена эквивалентность полного preview будущим
финансовым фактам, отсутствие preview mutations, replay и terminal guards.

Финальный backend: 278 suites / 3678 tests PASS в полном запуске;
dashboard suite отказалась стартовать из-за allowlist имени изолированной БД.
Она отдельно прошла на разрешённой локальной test DB: 16/16.
Итого 279 suites / 3694 tests, product source во время финальных проверок
не изменялся. Предыдущий неполный запуск упал на Node heap 2 GB и не считается
результатом кандидата; финальный выполнен с лимитом 6 GB.

Typecheck/build PASS; оба exact-image gates проверили identity, invalid flags,
healthy runtime и degraded readiness 503. Security gate PASS, npm audit 0,
Semgrep 74 rules / 799 files / 0 findings, Gitleaks 2 commits / 0 findings,
Trivy обоих images: 0 HIGH/CRITICAL и secrets. RepoWise live change risk
72.5 percentile / Elevated; coverage map отсутствует, поэтому выполнен весь
набор тестов. Flutter не менялся и повторно не тестировался.

## Исправление существующих записей

Read-only manifest зафиксировал 14 scheduled/planned v1 lessons с `none`,
положительными frozen rates и одним active template v1. 8 cancelled lessons
исключены. Один standalone lesson имеет personal-account funding с нулевой
ценой, 13-й recurrence намеренно не имеет резерва: остаток 12 уже распределён.

На isolated restore проведены те же existing preview/commit services,
template command, replay и reconciliation. В production actor получен из
действующей Windows-сессии: `GET /api/access/me`, account ID сверяется с token
subject и заранее проверенным оператором, capability повторяется на commit.
Auth tokens не создавались и не сохранялись; передавались только в stdin.

Production: HTTP preview всех 14 — PASS, затем обычные signed PUT и replay
каждого — PASS. Template-only amendment через existing
`PlatformIntegrityService`: expected versions, plan/series locks, immutable
audit, outbox; меняется только teacher rule и версии, без rematerialization.
Планы занятий получили append-only revision; новые начисления не создавались.

Исходный frozen digest закреплён до изменений и сверяется также при resume и
verify. Финальный read-only результат: scheduled `none` 0, `standard` 14,
active-template `none` 0, reserves 12, cancelled historical `none` 8;
snapshots, reservation history и client/teacher facts неизменны.
Readiness `ok`, reconciliation `issues=[]`, poison/dead-letter/pending events
и due emails 0. API error markers после cutover 0; production monitor PASS.

## Backup и rollback

Encrypted copies находятся на сервере и в
`C:/Users/Alinka/Documents/MagicMusicCRM Backups/2026-09-03/`.
Для каждой проверен SHA-256. Все restores выполнялись в отдельных внутренних
Docker networks/volumes без доступа к live DB.

| Backup | Байты | SHA-256 |
| --- | ---: | --- |
| Pre-rehearsal `20260903T104720Z` | 244496 | `f98ac0031ac40313f542c3d07f1d300c88b3f9b7fb2ee344aa39a0e287051ea6` |
| Pre-cutover `20260903T110304Z` | 244624 | `8d67360a803ccc79a10d2e760fe91d0941bcb2ae784e5951e08c09dde9fad066` |
| Post-repair `20260903T110703Z` | 250640 | `ea14abab128a0a9a59692ba278679a5b182895f1af6d35713816f8171ab183ca` |

Первая копия: bridge/210 restore и final/bridge restore с repair rehearsal.
Pre-cutover и post-repair: final/bridge restore, migration и reconciliation
PASS. Автоматический image-only rollback cutover настроен на новый bridge
`2ce1f16f` с сохранением 0147. Старый 210 и прежний `bf25d357` используют
несовместимый SQL conflict target; возвращать их после 0147 нельзя.
Не менять историю или запускать down migration для обхода этого ограничения.
Bridge имеет тот же runtime: общий дефект требует forward fix. Исправление
данных отменяется только новой компенсирующей audited/versioned командой.

Guarded deployment/repair artifacts:
`/opt/magicmusiccrm/releases/1.5.30-210-hotfix1-89c3c36f/`.
Raw logs, private manifest и rehearsal scripts локально:
`dist/incident-210-lesson-edit/`; в git их нет. Production dump, tokens,
секреты, исходные IDs учеников и финансовые payloads не коммитились.
