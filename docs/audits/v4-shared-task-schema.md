# V4 SharedTask schema and conservative migration — T6.1.1

## Результат

- Migration `0092` создаёт `SharedTask`, `TaskAudience`, `TaskClose`, persisted reminder, append-only `TaskAudienceResolutionAudit` и legacy link proof.
- Audience хранится selector-ами `user`, `branch`, `allBranches`; recipient-specific task state не создаётся.
- `TaskClose` уникален по задаче, resolution audit и close facts защищены от UPDATE/DELETE.
- Runtime schedule constraint допускает только all-day date или строгий interval `end > start`.
- Legacy backfill объединяет только полностью совпадающие payload/creator/created timestamp с разными явными recipients.
- Неоднозначные legacy rows сохраняются как отдельные SharedTask; каждая исходная строка имеет lossless link и fingerprint.
- Down migration fail-closed при наличии runtime SharedTask.

## Проверки

| Проверка | Результат |
|---|---:|
| Exact/ambiguous migration fixture | PASS |
| 2 exact legacy copies → SharedTask | 1 |
| 2 ambiguous legacy rows → SharedTask | 2 |
| Legacy facts linked | 4/4 |
| Audience rows preserved | 4/4 |
| Append-only audit guard | PASS |
| Migration down→up | PASS |
| TypeScript typecheck | PASS |

Команда:

```text
npm --prefix server test -- --runTestsByPath src/crm/tasks/shared-task-migration-postgres.integration.spec.ts
```
