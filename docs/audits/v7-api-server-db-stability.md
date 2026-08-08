# V7 — сквозная стабильность приложения, API, сервера и DB

**Дата:** 2026-08-08

**Production:** `https://api.magicmusiccrm.ru/api`

**Итог:** **PASS**

## Что проверено

- 275 production Flutter wire-call sites и 318 backend routes;
- DTO, capability/RBAC, actor-safe payloads и DB transaction boundaries;
- все 114 production migrations, constraints, indexes, locks и очереди;
- Client/Teacher/Admin/Manager/Director на Windows и Android 15;
- logout, cold restart и переключение аккаунтов;
- realtime invalidation, platform outbox и автоматическое завершение Lesson;
- API/Caddy logs и HTTPS после стабилизации deployment.

## Найденные и исправленные корни

### 1. Platform outbox не имел consumer

Сервер атомарно записывал audit/outbox вместе с бизнес-операциями, но production-код
никогда не вызывал `claimOutbox`. Поэтому DB commit был успешным, а межоконное/realtime
обновление могло не дойти без явной ошибки.

Добавлен один общий worker поверх уже существующего lease/retry/dead-letter API. Он:

- ждёт готовности `RealtimeBus` и не подтверждает событие раньше;
- доставляет access, CRM, schedule, task и commerce invalidations;
- повторяет временную ошибку, dead-letter-ит неизвестную после лимита;
- показывает pending/dead-letter/age в `/api/health/ready`;
- пишет warning для retry и не оставляет ошибку бесшумной.

Production proof: зависшее `commerce.subscription.changed` обработано самим worker:
`claimed=1 published=1 retry=0 deadLetter=0`; DB queue стала `0/0`.

### 2. Completion worker был выключен и видел legacy Lesson

Production `.env` сохранял `LESSON_COMPLETION_WORKER_ENABLED=false`. Одновременно старая
выборка считала due все Lesson, включая 445 прошедших и 11 387 будущих legacy-записей
без выбранного типа списания/оплаты преподавателю.

Worker включён, а claim/metrics ограничены обязательным
`lesson_settlement_plans.state='planned'`. Это сохраняет требуемую атомарную автоматику
для новых занятий и исключает финансовое списание исторических записей без решения
сотрудника. Тест отдельно доказывает, что legacy Lesson не claim-ится.

## Автоматические проверки

| Gate | Результат |
|---|---:|
| TypeScript / Nest build | PASS / PASS |
| Backend full | 156/156 suites; 1244/1244 tests |
| Actor Matrix + payload leak + route policy | 77/77 |
| Outbox/health/DB targeted | 17/17 |
| Flutter full | 648/648 |
| Windows real production accounts | 2/2 |
| Android 15 real production accounts | 2/2 |
| v4/v6/v7 inventory stale checks | PASS |

## Production после запуска

| Проверка | Значение |
|---|---:|
| Image | `sha256:8744ae77276ddcb262fc6e317211ba960f0ec4062856e0a602f6c2ee01539142` |
| API health / restarts / OOM | healthy / 0 / false |
| Readiness checks | все `ok` |
| Completion due/claimed/retry/poison | 0/0/0/0 |
| Outbox pending/dead-letter | 0/0 |
| Invalid indexes / unvalidated constraints / blocked sessions | 0/0/0 |
| HTTPS burst | 30/30 |
| API errors после stable start | 0 |
| Caddy 5xx после stable start | 0 |

Десять `502` в журнале ограничены секундами контролируемого пересоздания API; после
health transition они не повторились.

## Безопасность данных и rollback

До изменения сохранены verified DB dump, backend, Compose, `.env` и предыдущий image:
`/opt/magicmusiccrm/backups/manual/pre-api-db-stability-20260808T145521Z`.
Миграций и ручных изменений бизнес-данных не выполнялось. Legacy Lesson без финансового
решения намеренно не backfill-ятся: это исключает несанкционированные списания.
