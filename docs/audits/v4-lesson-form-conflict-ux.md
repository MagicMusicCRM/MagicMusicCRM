# T4.3.1 — Lesson form & conflict UX evidence

**Дата:** 2026-07-26
**Требования:** REQ-LESSON-001, REQ-SCHED-001
**Дизайн:** `schedule_lifecycle.md §5–7`
**Результат:** PASS

## Единая форма

- Раздельные Student/Lead picker заменены одним actor-scoped Client selector через `GET /crm/clients/search`.
- Выбранный клиент передаётся только как явный `clientRef: {type, id}`; UUID-тип не угадывается.
- `isTrial` остаётся независимым boolean: Lead не включает и не блокирует toggle автоматически.
- Create требует teacher, branch, room, interval, completion type, client charge type/value и teacher compensation type/value.
- Для списания по абонементу Student выбирает конкретный subscription; Lead не получает subscription option.
- Immutable completion/financial/compensation snapshot видим, но заблокирован на edit.
- Edit/drag передают `expectedVersion`; schedule projection возвращает version и role-safe snapshot-поля.

## Conflict UX

- Legacy preview `/crm/schedule/conflicts` блокирует submit до mutation.
- Authoritative `LESSON_CONSTRAINT_VIOLATIONS` разбирается как полный список violations, а не одна строка ошибки.
- Для каждого violation показаны понятный русский label, resource type/id и ссылки на `conflictingLessonIds`.
- Старые `force: true` payload, admin-only «Всё равно назначить» и повтор mutation удалены из create/edit/drag UX.
- Preview остаётся advisory: при его недоступности authoritative command всё равно fail-closed проверяет полный constraint engine.

## Command metadata и projection seam

- `MagicApiClient` добавляет `Idempotency-Key` и `X-Request-Id` ко всем mutation requests.
- Оба значения создаются один раз на logical request и сохраняются при connection/401 retry.
- `listLessons` возвращает `version` всем actor-safe projections.
- Client charge/subscription snapshot возвращается только при `canReadStudentFinance`; teacher compensation — только при `canReadTeacherRates`.
- Новых routes/capabilities нет; Actor Matrix остаётся неизменной.

## Widget contract

`test/features/v4/lesson_form_test.dart` доказывает:

1. Lead/Student выбираются одним Client selector, а trial независим;
2. create отправляет полный required snapshot без legacy `status`/`force`;
3. preview conflict не создаёт запись и не показывает bypass;
4. authoritative 422 показывает несколько structured violations и lesson link;
5. edit отправляет `expectedVersion` и не меняет immutable snapshot.

Существующий pagination regression переведён на `/crm/clients/search`: клиент вне первой страницы находится серверным запросом и остаётся выбранным.

## Quality gates

| Gate | Результат |
|---|---:|
| Exact Lesson form widget contract | 4/4 tests |
| Client search regression | 1/1 test |
| MagicApiClient mutation metadata | PASS |
| Schedule service regression | 53/53 tests |
| Backend typecheck/build | PASS / PASS |
| Full backend | 127/127 suites, 1059/1059 tests |
| Flutter analyze | No issues found |
| Full Flutter | 399/399 tests |

## Acceptance

- Один Lead или Student выбран как typed ClientRef.
- Trial marker не зависит от типа клиента.
- Invalid preview/authoritative conflict понятен и не создаёт/не изменяет Lesson.
- Business-role constraint override отсутствует.
- Create/edit/drag используют единый versioned v4 command boundary.
