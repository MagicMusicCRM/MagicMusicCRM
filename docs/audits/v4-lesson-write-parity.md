# MagicMusicCRM v4 — Unified Lesson Write Parity

**Task:** T4.2.2
**Requirements:** REQ-LESSON-001, REQ-SCHED-001
**Result:** PASS
**Date:** 2026-07-26

## Unified command boundary

`POST /api/crm/lessons` и `PATCH /api/crm/lessons/:id` теперь направлены в
один `LessonCommandService`. Edit и drag используют один update command:
полный edit DTO и частичный drag DTO сначала преобразуются в одинаковый
effective draft.

Каждая команда требует:

- `Idempotency-Key` и `X-Request-Id`;
- `expectedVersion` для update;
- один typed `ClientRef` (`lead|student`), при этом legacy `studentId/leadId`
  нормализуются compatibility adapter-ом;
- Teacher, Branch, Room, start и duration;
- independent `isTrial`;
- completion type, client charge type/value и teacher compensation type/value.

Legacy `force` больше не обходит constraints. Новый Lesson всегда создаётся в
`scheduled`; Lead не принуждается к trial, поэтому `ClientRef` и `isTrial`
остаются независимыми.

## Transaction и immutable snapshot

Create заранее получает deterministic Lesson UUID из actor-scoped
idempotency key. `PlatformIntegrityService` фиксирует в одной PostgreSQL
transaction:

1. idempotency reservation/fingerprint;
2. aggregate version;
3. resource advisory locks;
4. полный constraint result;
5. Lesson и immutable `LessonSnapshot`;
6. audit и redacted outbox reference;
7. replay result.

Update проверяет aggregate/Lesson version, блокирует старые и новые resources,
собирает недостающие поля из существующего valid snapshot и увеличивает
версию ровно один раз. Financial/completion/client/trial snapshot нельзя
заменить через edit/drag.

## Constraint parity

Один и тот же overlapping draft отправлен тремя способами:

- create с complete DTO;
- edit с complete DTO;
- drag с partial DTO (`expectedVersion + scheduledAt`).

Все три вернули byte-equivalent `LESSON_CONSTRAINT_VIOLATIONS` с
`TEACHER_OVERLAP`, `CLIENT_OVERLAP`, `ROOM_OVERLAP` и одинаковыми
resource/Lesson refs. Ни одна invalid command не оставила Lesson,
idempotency, version, audit или outbox partial state.

## Проверки

| Gate | Result |
|---|---:|
| Exact PostgreSQL contract suite | 1/1 suite, 1/1 test |
| Same invalid create/edit/drag response | PASS |
| Duplicate create replay / Lesson count | PASS / 1 |
| Valid drag version increment | PASS |
| Actor Matrix | 1512/1512 decisions, 1228 allow, 284 deny |
| Access coverage | 252/252 private routes, unexplained allow 0 |
| Current-state inventory | 264 routes, 573 DTO fields, 0 unowned |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 125/125 suites, 1068/1068 tests |

Exact command:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/schedule/lesson-write-parity.integration.spec.ts
```
