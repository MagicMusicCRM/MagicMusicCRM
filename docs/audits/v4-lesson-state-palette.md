# V4 Lesson state/reservation palette — T4.3.2

**Дата:** 2026-07-26

**Требования:** REQ-LESSON-003, REQ-CLIENT-003

**Результат:** PASS

## Что изменено

- Добавлена закрытая визуальная модель `LessonStateToken`: `neutral`,
  `success`, `rescheduled`.
- Единый mapper вычисляет presentation token только из authoritative
  `lifecycleState + reservationState`. Legacy `status` используется лишь как
  compatibility fallback; редактируемого поля цвета или «типа занятия» нет.
- `ScheduleService.listLessons` возвращает состояние последней terminal
  reservation в actor-scoped Lesson projection. Flutter legacy mapper сохраняет
  его как `reservation_state`.
- Общие `LessonStateBadge` и `LessonTrialBadge` заменили локальные status/trial
  pills.

## Матрица проекции

| Lifecycle | Reservation | Token | UI |
|---|---|---|---|
| `scheduled` | нет | `neutral` | серый, «Запланировано» |
| `scheduled` | `reserved` | `success` | зелёный, «Забронировано» |
| `successfully_completed` | любое | `success` | зелёный, «Завершено» |
| `rescheduled` | любое | `rescheduled` | красный, «Перенесено» |

`trial` не участвует в выборе цвета и всегда отображается отдельным золотым
маркером.

## Покрытые surfaces

- расписание по аудиториям: day canvas и month view;
- расписание по преподавателям;
- административный список занятий;
- клиентские «Предстоящие» и «История»;
- связанные Lesson-карточки и лента дат в карточке ученика.

Конфликт расписания остаётся отдельным blocking/error overlay и имеет приоритет
над state accent, не меняя саму state projection.

## Верификация

- `flutter test test/features/v4/lesson_state_palette_test.dart` — **6/6 PASS**;
- trial-label regression + palette suite — **7/7 PASS**;
- `flutter analyze` — **PASS**, 0 issues;
- `flutter test` — **405/405 PASS**;
- backend `npm run typecheck` — **PASS**;
- backend `npm run build` — **PASS**;
- backend full Jest/PostgreSQL — **127/127 suites, 1059/1059 tests PASS**.
