# T8.1.4 — Platform Primitives Evidence

Проверка выполнена 2026-07-25 на реальном локальном PostgreSQL 16.4.

## Реализованный контракт

- Additive migration `0075_platform_integrity_primitives`:
  `aggregate_versions`, `idempotency_records`,
  `platform_outbox_events` и correlation-поля `audit_events`.
- Один transaction boundary для idempotency reservation, optimistic version,
  domain callback, audit, outbox и stored result reference.
- Один actor/operation/key с одинаковым canonical fingerprint возвращает
  сохранённый result; другой fingerprint и stale version возвращают HTTP 409.
- Outbox claim использует `FOR UPDATE SKIP LOCKED`, lease, bounded retry,
  ownership check, publish marker и видимый dead-letter state.
- Generic outbox payload пропускает только safe invalidation keys; контакты,
  финансовые поля, comment/message body, токены и произвольный текст не
  попадают в envelope.
- Down migration отказывается удалять таблицы или correlation-поля, если в
  них уже появились v4 facts.

## Проверки

| Gate | Результат |
|---|---:|
| `npm --prefix server run typecheck` | PASS |
| `npm --prefix server run build` | PASS |
| Exact PostgreSQL integration suite | 1 suite, 5/5 tests |
| Platform utility unit suite | 1 suite, 4/4 tests |
| Полный backend regression | 102/102 suites, 927/927 tests |
| Migration `down → up` на пустых platform stores | PASS |
| Guarded `down` с существующим aggregate version fact | REJECTED, marker сохранён |
| Остаточные `v4-test:*` facts после suites | 0/0/0/0 |

Exact gate:

```powershell
npm --prefix server test -- --runTestsByPath src/platform/platform-integrity-postgres.integration.spec.ts
```

Интеграционная suite доказывает:

1. два параллельных одинаковых payload/key выполняют domain callback один раз
   и возвращают одинаковые result/audit/outbox references;
2. два разных payload с одним key дают один commit и один 409 conflict;
3. исключение domain callback откатывает reservation, version, audit и outbox;
4. stale expected version даёт 409 без дополнительных facts;
5. два worker получают разные события, а retry/publish/dead-letter состояния
   сохраняются и проверяют ownership.
