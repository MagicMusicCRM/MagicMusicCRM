# V4 read-only Teacher calendar — T4.3.3

**Дата:** 2026-07-26

**Требования:** REQ-TEACHER-001, REQ-PRIV-001

**Результат:** PASS

## Что изменено

- Teacher calendar ограничен responsive-представлениями `День` и `Неделя`;
  широкая компоновка использует segmented control, узкая — компактный selector.
- Добавлены явные loading, empty, error и retry states без подмены ошибки пустым
  расписанием.
- Исходный actor-scoped запрос сохранён: текущий профиль сопоставляется с
  Teacher по `profile_user_id`, затем запрашиваются только занятия с его
  `teacherId`.
- Карточка занятия стала полностью read-only. Она показывает authoritative
  lifecycle/reservation badge, отдельный trial marker, место и план занятия.
- Safe drilldown открывает только историю назначенных этому Teacher занятий и
  actor-scoped список домашних заданий клиента.
- Удалены edit plan, create homework и любые create/edit/drag/reschedule/cancel/
  attendance controls. Виджет не выполняет POST/PATCH.

## Граница доступа

- Flutter route `MessengerScreen(role: teacher) → Расписание` ведёт на тот же
  read-only widget.
- История ученика запрашивается с одновременными `studentId + teacherId`;
  история trial Lead дополнительно фильтруется внутри уже assigned-only выдачи.
- Homework drilldown использует только `studentId` или `leadId`; для group
  Lesson без прямого клиента возвращается пустой safe projection.
- PostgreSQL integration вызывает Lesson update от реального Teacher actor,
  получает `403` и подтверждает неизменные `version`/`notes`.
- Production backend-код и API-контракты не изменены; в `server/` добавлена
  только интеграционная гарантия read-only boundary.

## Верификация

- `flutter test test/features/v4/teacher_schedule_read_only_test.dart` —
  **5/5 PASS**;
- identity regression — **1/1 PASS**;
- `flutter analyze` — **PASS**, 0 issues;
- `flutter test` — **410/410 PASS**;
- backend `npm run typecheck` — **PASS**;
- backend `npm run build` — **PASS**;
- Lesson write parity PostgreSQL — **2/2 PASS**;
- backend full Jest/PostgreSQL — **127/127 suites, 1060/1060 tests PASS**.
