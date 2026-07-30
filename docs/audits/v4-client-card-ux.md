# V4 Client Card, archive and comment UX — T3.3.2

Дата: 2026-07-30  
Статус: PASS

## Role-aware card

- Production card launcher ожидает server role и только затем создаёт нужную
  карточку; legacy staff loaders не запускаются для Teacher.
- Teacher использует actor-scoped
  `GET /crm/clients/:type/:id/card` и отображает только Lesson, Homework и
  явно shared Comment sections.
- Contacts, representatives, tasks и finance не строятся даже при ошибочно
  добавленном лишнем ключе payload.
- Tabs горизонтально прокручиваются на 320 dp; loading, empty, error/retry и
  archived tombstone состояния явные.
- Список учеников Teacher больше не раскрывает phone/notes локально и открывает
  ту же ограниченную карточку.

## Archive and comments

- Archive control отсутствует у Teacher/Admin/Manager и доступен только
  Director/system_admin.
- UI выполняет preview, показывает future/finance warnings и связанные
  ClientRef, затем отправляет `expectedVersion`, `confirm=true` и безопасный
  reason code.
- Связанная Lead/Student запись не архивируется вместе с выбранной.
- Comment toggle отправляет независимый `sharedWithTeacher`,
  `expectedVersion` и audit reason; comment kind не подменяется.

## Верификация

- `client_card_roles_test.dart`: 4/4 tests.
- Existing Client Card + finance role regression: 18/18 tests.
- Flutter analyze: clean.
