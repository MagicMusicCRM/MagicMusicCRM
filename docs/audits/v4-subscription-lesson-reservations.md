# V4 Subscription/Lesson reservations — T5.3.2

## Результат

- Lesson create, finite series и reschedule-successor атомарно создают reservation для активного абонемента.
- Allocation блокирует issued subscription, проверяет клиента и доступный объём с учётом использованных и уже зарезервированных единиц.
- Replace/cancel и completion сериализуются через issued subscription + reservation row locks.
- Settlement использует фактически перенесённый reservation; если cancel уже снял покрытие, новый subscription write-off не создаётся.
- Completion терминализирует reservation в той же transaction, что Lesson state и immutable financial facts.
- После commit schedule/client-finance projections получают body-safe invalidation; проверенный runtime lag меньше 2 секунд.
- Future lessons при cancel/replace не удаляются.

## Проверки

| Проверка | Результат |
|---|---:|
| Exact PostgreSQL race suite | 2/2 PASS |
| Targeted commerce/schedule regression | 19/19 PASS |
| TypeScript typecheck | PASS |
| Duplicate client/teacher facts | 0 |
| Lost future lessons | 0 |
| Post-commit invalidation target | <2 s |

Команда exact gate:

```text
npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-lesson-race-postgres.integration.spec.ts
```
