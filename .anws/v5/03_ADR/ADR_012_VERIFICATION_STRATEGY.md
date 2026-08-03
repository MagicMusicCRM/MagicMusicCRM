# ADR-012 — Многоуровневая стратегия проверки v4

**Status:** Accepted  
**Date:** 2026-07-25  
**Influence scope:** все системы и release process  
**Requirements:** все REQ v4

## Context

v4 изменяет доступ, деньги, расписание и конкурентность — области, где один happy-path E2E не доказывает корректность. При этом проект уже работает в production, поэтому migration drift и регрессия существующих функций опаснее отсутствия новой косметики.

## Decision

Каждая вертикаль проходит минимально достаточные слои:

1. **Static gates:** `flutter analyze`, backend typecheck/build, migration lint.
2. **Unit:** capability evaluator, interval constraints, state machines, money rounding, derived metrics.
3. **Integration with PostgreSQL:** transaction boundaries, concurrent claims, idempotency, projections, migrations.
4. **Contract/actor matrix:** шесть ролей, safe DTO shape, old façade/new service parity в переходный период.
5. **Widget/golden:** role surfaces, mobile/desktop variants, empty/error/conflict states.
6. **E2E on Windows and Android:** ключевые user stories по реальному staging API.
7. **Data reconciliation:** payment/ledger/subscription/lesson totals до и после миграции.
8. **Operational gates:** backup, restore rehearsal, worker backlog, outbox lag, rollback smoke.

Ни один Sprint не закрывается без собственной `INT-S{N}` проверки. Production rollout выполняется staged; write-heavy migrations имеют feature flag/compatibility phase и rollback plan.

## Options considered

| Option | Плюсы | Минусы | Решение |
|---|---|---|---|
| Только unit tests | Быстро | Не ловит SQL/RBAC/integration drift | Отклонено |
| Только E2E | Близко к пользователю | Медленно, плохо локализует гонки | Отклонено |
| Layered risk-based gates | Покрывает логику, контракты и runtime | Требует test data и дисциплины | Принято |

## Consequences

- Task checklist обязан содержать команду/сценарий проверки каждой задачи.
- Отсутствующая локальная test dependency является блокером baseline, а не допустимым «известным исключением».
- Owner acceptance следует после технических gates, но не заменяет их.
- Evidence хранится в v4 review/release документах, а не смешивается с v3 evidence.

## Verification

- `05_TASKS.md` содержит test method и concrete command у каждой L3-задачи.
- Каждый Sprint заканчивается `INT-S{N}`.
- `05_TASKS_REVIEW.md` доказывает полное прямое/обратное покрытие.
- `07_CHALLENGE_REPORT.md` не содержит незакрытых Critical/High.

## Design links

- Все документы `04_SYSTEM_DESIGN/*.md`
- `05_TASKS.md`
