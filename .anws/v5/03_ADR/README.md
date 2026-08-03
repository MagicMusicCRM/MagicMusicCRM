# MagicMusicCRM v4 — Decision Index

**Статус:** Active  
**Дата:** 2026-07-25

## Наследованные решения v3

ADR-001–ADR-006 сохраняют силу без изменения:

| ADR | Решение |
|---|---|
| ADR-001 | NestJS + TypeScript, PostgreSQL, Redis, WebSocket и Docker Compose |
| ADR-002 | Серверная модель auth/session |
| ADR-003 | Приватная файловая модель |
| ADR-004 | Realtime и messenger runtime |
| ADR-005 | Deployment, backup и recovery |
| ADR-006 | Security gates как блокирующая часть релиза |

## Решения v4

| ADR | Решение | Статус |
|---|---|---|
| ADR-007 | Capability-пакеты, персональные overrides и hard invariants | Accepted |
| ADR-008 | Жизненный цикл занятия и серверный constraint engine | Accepted |
| ADR-009 | Неизменяемые финансовые факты и снимки выданных абонементов | Accepted |
| ADR-010 | Account-scoped desktop workspace и модель конкурентности вкладок | Accepted |
| ADR-011 | Версии агрегатов, idempotency и transactional outbox | Accepted |
| ADR-012 | Многоуровневая стратегия проверки v4 | Accepted |

Все новые решения трассируются к [`01_PRD.md`](../01_PRD.md), [`02_ARCHITECTURE_OVERVIEW.md`](../02_ARCHITECTURE_OVERVIEW.md) и проектам систем в `04_SYSTEM_DESIGN/`.
