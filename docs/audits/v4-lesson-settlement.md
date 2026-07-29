# V4 idempotent Lesson settlement — T5.1.1

**Дата:** 2026-07-29

**Требования:** REQ-LESSON-002, REQ-SUB-004

**Результат:** PASS

## Что реализовано

- Добавлен transaction-scoped `LessonSettlementPort` с отдельными service и
  repository слоями.
- Settlement сериализуется PostgreSQL advisory lock по `lessonId`; повторный
  или параллельный вызов возвращает те же immutable fact IDs и значения.
- Migration `0087` создаёт по одному unique fact на Lesson:
  `lesson_client_charge_facts` и `lesson_teacher_compensation_facts`.
- Оба типа фактов append-only: `UPDATE` и `DELETE` отклоняются immutable
  trigger-ом.
- Денежные значения хранятся в целых minor units с `RUB` currency code;
  subscription consumption хранит units отдельно от money.
- Settlement разрешён только для `successfully_completed` Lesson с valid
  snapshot; ошибка не оставляет частичного факта.

## Teacher compensation

- Поддержаны только подтверждённые владельцем варианты:
  `fixed`, `hourly`, `none`.
- `fixed`: итог равен зафиксированной сумме за занятие.
- `hourly`: `round(rate × 100 × snapshot.durationMinutes / 60)`.
- `none`: ставка и итоговый fact принудительно равны нулю даже при устаревшем
  ненулевом value в исходной форме.
- Процентная оплата преподавателя не добавлена.

Длительность добавлена в immutable `LessonSnapshot`. Для существующих
snapshot она backfill-ится из Lesson; старые insert-paths без явного поля
совместимо заполняются `BEFORE INSERT` trigger-ом.

## Граница скидок

Subscription discount не смешивается с teacher compensation. Для будущего
issue flow сохраняется контракт `percent xor fixed`; процент считается от
указанной базовой суммы, например `8000 - 20% = 6400`.

## Верификация

- exact PostgreSQL settlement suite — **1/1 suite, 2/2 tests PASS**;
- 12 параллельных settlement-вызовов — одинаковый result, **1 client fact +
  1 teacher fact**;
- fixed/hourly/none и округление hourly — **PASS**;
- immutable fact mutation rejection — **PASS**;
- migration `0087` down→up — **PASS**;
- Lesson schema/write/series/transition/settlement regression —
  **5/5 suites, 7/7 tests PASS**;
- Actor Matrix + payload leak — **2/2 suites, 8/8 tests PASS**;
- backend typecheck — **PASS**;
- backend build — **PASS**;
- backend full Jest/PostgreSQL — **128/128 suites, 1062/1062 tests PASS**.

API routes и Flutter-код в задаче не менялись.
