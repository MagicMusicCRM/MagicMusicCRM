# V4 durable Lesson completion worker — T8.2.1

**Дата:** 2026-07-29

**Требования:** REQ-LESSON-002, REQ-AUDIT-001

**Результат:** PASS

## Что реализовано

- Migration `0088` добавляет durable `app.lesson_completion_work` с
  состояниями `claimed`, `retry`, `completed`, `poison`, номером попытки,
  lease-владельцем, временем доступности и ссылками на terminal facts.
- Due Lesson выбираются по PostgreSQL UTC clock ограниченными batch через
  `FOR UPDATE SKIP LOCKED`. Истёкший lease доступен другому worker; истёкшая
  последняя попытка переводится в видимый `poison`.
- Retry использует bounded exponential backoff: 5, 10, 20… секунд, максимум
  300 секунд. В `last_error` сохраняется только безопасное имя ошибки.
- Worker запускается с интервалом 15 секунд при
  `LESSON_COMPLETION_WORKER_ENABLED=true`. До отдельного rollout-enable флаг
  по умолчанию выключен; due work остаётся в PostgreSQL и не теряется.

## Transaction boundary

Одна `PlatformIntegrityService` transaction:

1. резервирует стабильный idempotency key `lesson-completion:<lessonId>`;
2. блокирует owned claim и ещё `scheduled` Lesson ожидаемой версии;
3. переводит Lesson в `successfully_completed`;
4. создаёт один client charge fact и один teacher compensation fact через
   `LessonSettlementPort`;
5. терминализирует активную reservation;
6. добавляет immutable `LessonTransition` со ссылками на оба fact;
7. отмечает durable claim как `completed`;
8. фиксирует audit `crm.lesson_completed` и safe outbox
   `schedule.lesson.changed`.

Любая ошибка откатывает Lesson, facts, transition, claim-completion, audit и
outbox вместе. Падение процесса после commit не требует in-memory
acknowledgement: новый worker видит terminal Lesson и не создаёт повтор.

Teacher compensation остаётся только `fixed`, `hourly`, `none`; процентная
оплата преподавателю не добавлялась.

## Health и metrics

`GET /api/health/ready` теперь включает:

- `due`;
- `claimed`;
- `retry`;
- `poison`;
- `completed`;
- `oldestDueSeconds`;
- `maxAttempts`.

Worker health становится `degraded`, если есть poison work или возраст
старейшего due Lesson превышает 120 секунд.

## Верификация

- exact PostgreSQL worker suite — **1/1 suite, 4/4 tests PASS**;
- two-worker claim — один terminal state, transition, client fact, teacher
  fact, audit, outbox и idempotency result;
- completion latency fixture — **≤60 секунд после `endAt`**;
- expired lease reclaim после kill-before-commit — **PASS**;
- kill-after-commit + restart без duplicate facts — **PASS**;
- bounded retry и poison visibility/health — **PASS**;
- migration `0088` down→up — **PASS**;
- Lesson/platform regression — **8/8 suites, 18/18 tests PASS**;
- health + worker targeted — **2/2 suites, 8/8 tests PASS**;
- Actor Matrix + payload leak — **2/2 suites, 8/8 tests PASS**;
- backend full Jest/PostgreSQL — **129/129 suites, 1067/1067 tests PASS**;
- backend typecheck/build — **PASS**;
- v4 inventory — **266 routes, 591 DTO fields, 5 schema inventories,
  unowned=0**.

API business routes и Flutter-код не менялись.
