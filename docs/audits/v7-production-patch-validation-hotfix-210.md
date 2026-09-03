# Production PATCH validation hotfix — 2026-09-03

По прямой команде владельца «выкатывай» выпущен server
`1.5.30+210-hotfix.2`. Клиент остаётся `1.5.30+210`; клиентские пакеты
и update manifests не менялись. Миграций и исправлений production-данных нет.

## Исправления

PATCH источника клиента и дополнительного поля пропускал явный `null`
через `@IsOptional`, после чего проверка обязательного текста вызывала
`.trim()` и возвращала 500. `canonicalName`, `displayName`, `label` теперь
проверяются при любом значении, кроме `undefined`; null возвращает HTTP 400.
Пропущенные поля остаются допустимыми для частичного обновления.

При сохранении заметки занятия реальный ValidationPipe создавал экземпляр
DTO с собственными незаполненными полями. Guard ошибочно считал их попыткой
изменить защищённые данные и возвращал 422. Guard игнорирует только
`undefined`; явно переданные защищённые null/false/0 по-прежнему отклоняются.
Заметку можно сохранить, очистить строкой или null. Version, idempotency,
audit/outbox и финансовые команды остаются в существующем контуре.

## Точный кандидат и rollback

| Назначение | Revision | Image ID |
| --- | --- | --- |
| Candidate | `61937d477d9a85bb32dbc81e39ec1399e42f5557` | `sha256:2d3c369d949ef53d8965869c7da7e3022d01f3ff7f9af140c857b9979615e814` |
| Rollback | `89c3c36f8f0696df771d6934c6c2f5b0ba050d9f` | `sha256:70b5263383d8d5d044931017a31c2934b99f3cb3e19dddcd7ac539d0c2983051` |

Candidate tag: `magicmusiccrm-server:1.5.30-210-hotfix2-61937d47`.
Rollback tag: `magicmusiccrm-server:1.5.30-210-hotfix1-89c3c36f`, version
`1.5.30+210-hotfix.1`. Обе версии используют migration
`0147_lesson_reservation_history`; down migration не нужна и не запускалась.
Rollback возвращает прежнее поведение валидации, сохраняя схему и историю.
Старые pre-0147 runtime с несовместимым SQL conflict target не подходят.

Две локальные Docker-сборки остановились на сетевом `npm ECONNRESET`.
Финальный образ собран на сервере штатным Dockerfile из `git archive`
точного revision; `.env` в контекст не входил. Архив после передачи сверён:
SHA-256 `a99d06c7b4e9d1f51d8d42520d19c5ed41b87e0bc9483321592970b1bcca902a`.
OCI revision/version, non-root user и readiness healthcheck проверены.

## Автоматические проверки

| Проверка | Результат |
| --- | --- |
| Регрессии через настоящий ValidationPipe | Сначала 6 отказов; после исправления 54/54 теста в четырёх наборах |
| Полный backend на отдельной локальной PostgreSQL | 280 suites / 3708 tests PASS, 529.191 s |
| HTTP + Windows/API/БД | Runner 24 PASS / 0 FAIL: 22 HTTP-сценария, один live Windows сценарий, один набор из пяти Windows UI-сценариев; 43 HTTP-запроса, 0 ответов 5xx |
| Готовый production image | Некорректные production flags отклонены; live/ready 200; degraded readiness 503; healthcheck различает состояния; исправления проверены внутри image |
| Build, strict security gate, Gitleaks, Trivy | PASS; strict gate 11/11, npm audit 0, Gitleaks 0, Trivy HIGH/CRITICAL 0 и secrets 0 |

HTTP/Windows run: `f02fbfb98ee14d6abeb81e674f2725d2`.
Проверены 13 пятниц в диапазоне 01.09–01.12.2026 и 12 резервов; сохранение,
повтор команды и очистка заметки не меняют расчёты, создают ожидаемые
audit/outbox записи. Windows работает с настоящим API и БД в отдельном
контуре. Production-финансовые команды для тестирования не выполнялись.
Flutter source не менялся; полный клиентский набор повторно не запускался.

RepoWise change risk: percentile 82.2 / Elevated, coverage map отсутствует;
поэтому выполнен полный backend-набор. Semgrep `p/default` расширил охват
до 210 правил / 800 файлов: **17 прежних findings**, полный scan завершился
с ненулевым кодом; это не zero-findings результат. Все затронутые этими
findings файлы неизменны относительно исходного revision. Разбор: 10
детерминированных секретов в тестовых fixtures, одно предупреждение об
инъекции свойства при постоянном ключе `x-request-id`, шесть предупреждений
в CLI-аудитах/отчётах с локальными путями и фиксированными командами.
Differential scan против `89253001f6fa` по четырём изменённым TS-файлам:
**0 новых findings**, exit 0. Эти результаты не означают отсутствия всех
возможных ошибок вне проверенных сценариев.

Из-за сборки на Linux exact-image gate выполнен рядом с image в отдельной
internal Docker network, без подключения к live DB. Он повторяет проверки
`scripts/v7_production_image_gate.ps1`. Два подготовительных запуска не
считаются PASS: сначала в новой БД отсутствовала bootstrap-роль
`magiccrm_app`, затем проверка Unix socket поймала временный сервер initdb
перед его перезапуском. В fixture добавлена роль и ожидание TCP-ready;
отдельная диагностика PostgreSQL подтвердила причину. Финальный полный gate
PASS, временные контейнеры и сеть удалены. Product image не изменялся.

## Backup и проверка возврата

Зашифрованные копии сохранены на сервере и вне него:
`C:/Users/Alinka/Documents/MagicMusicCRM Backups/2026-09-03/`.
SHA-256 каждой off-host копии совпадает с сервером.

| Backup | Байты | SHA-256 |
| --- | ---: | --- |
| Pre-cutover `20260903T153237Z` | 251232 | `5d3baea11e680ff721fca93f2e03fa659176c02a8bc2d21b51a0040f07ba1d71` |
| Post-cutover `20260903T153905Z` | 251232 | `d2cc9a0ef8ef2465e619fecec25d9bcb436a4a6a262b2791045870c37fcbcb75` |

Обе копии прошли штатный `verify-release-backup-compatibility.sh`:
восстановление в случайную internal network и новый PostgreSQL volume,
candidate migrations/reconciliation, затем rollback migrations/reconciliation
и read-only database probe. Rollback не применяет миграций; head остаётся
0147, обе reconciliation возвращают `issues=[]`. Временные ресурсы очищены.
Live volumes, секреты и финансовая история для проверки не изменялись.

## Production

Штатный `deploy-api-release.sh` завершился `DEPLOY_API_RELEASE|PASS`.
Перед открытием трафика проверены OCI identity, migration, DB constraints,
trigger function и reconciliation. Автоматический rollback настроен на
89c3c36f. Marker `DEPLOYED_REVISION` указывает на 61937d47.

Новый API стартовал в 15:38:07 UTC. Проверки в 15:39 и 15:40 UTC:
точный image healthy, restart count 0; публичный readiness
`ok`, все checks `ok`, reconciliation `issues=[]`. Read-only сверка с
pre-state: scheduled standard 14, scheduled none 0, active-template none 0,
reserved 12, historical cancelled none 8. Poison, unpublished/dead-letter
events и due emails — 0. API error markers и Caddy HTTP 5xx после старта — 0.
Production monitor дважды PASS, запущен с принудительным dry-run уведомлений.

Remote artifacts: `/opt/magicmusiccrm/releases/1.5.30-210-hotfix2-61937d47/`.
Локальные raw logs и verification scripts: `dist/release-210-hotfix2/`.
Они исключены из git; backups, env, tokens и PII не коммитились.
