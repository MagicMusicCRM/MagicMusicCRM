# V4 schedule concurrency/property suite — T4.4.1

**Дата:** 2026-07-29

**Требования:** REQ-SCHED-001, REQ-LESSON-002

**Результат:** PASS

## Покрытие

- `test:schedule-v4` объединяет unit/property и PostgreSQL integration
  проверки расписания в один воспроизводимый gate.
- Half-open interval engine проверяется на 2 000 детерминированных
  randomized cases с фиксированным seed: symmetry, translation invariance,
  overlap oracle и допустимая adjacency.
- Weekly series проверяется на 64 детерминированных randomized samples в
  `America/New_York`, `Europe/Berlin`, `Europe/Moscow` и
  `Australia/Sydney`. Для десяти occurrence каждого sample локальное время
  сохраняется, а UTC-шаг через DST равен только 167, 168 или 169 часам.
- Существующий atomic series test по-прежнему доказывает полный rollback на
  N-м конфликте и стабильный DST-aware результат через реальный
  `LessonSeriesCommandService`.

## Concurrency

- Два параллельных create в один интервал дают один accepted Lesson и один
  structured `422`; persisted overlap равен нулю.
- Два независимых Lesson, одновременно перетаскиваемые в один интервал,
  дают один успешный drag и один structured `422`; в target сохраняется
  ровно одна запись.
- Два reschedule одной версии дают один successor, один transition, один
  audit и один `409` stale loser.
- Два completion worker сохраняют один terminal Lesson, один client fact,
  один teacher compensation fact, один transition, один audit/outbox и
  stable replay result.

Победитель race не фиксируется по порядку запуска; фиксируется только
доменный инвариант «ровно один результат». Это исключает зависимость теста
от scheduler timing.

## Attendance inventory

`test/features/v4/schedule_regression_test.dart` инвентаризирует Flutter
routes и весь `lib/**/*.dart`:

- route с `attendance` — 0;
- API mutation path с `attendance` — 0;
- `AttendanceService` и mutation symbols — 0;
- attendance toggle/control/button/action — 0;
- UI-команды ручной отметки/сохранения посещаемости — 0.

Read-only analytics labels и legacy evidence не считаются mutation surface.

## Верификация

- exact schedule gate — **9/9 suites, 25/25 tests PASS**;
- Flutter schedule inventory — **1/1 test PASS**;
- backend full Jest/PostgreSQL — **129/129 suites, 1071/1071 tests PASS**;
- Flutter full regression — **411/411 tests PASS**;
- Flutter analyze — **PASS, 0 issues**;
- backend typecheck/build — **PASS**;
- `pubspec.lock` — **без изменений**.

Проверки выполнены на проектной версии Flutter `3.41.4`
(`ff37bef603469fb030f2b72995ab929ccfc227f0`) и Dart `3.11.1`, указанной в
`.metadata`. Новые package/runtime dependencies и business API не
добавлялись.
