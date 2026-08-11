# ADR-001 — RepoWise-first engineering workflow

- **Статус:** Accepted
- **Дата:** 2026-08-11
- **Владелец решения:** владелец продукта

## Контекст

Предыдущий governance-контур требовал от каждого агента загружать
версионированные PRD/backlog/system-design пакеты, выбирать фазовый workflow и
поддерживать отдельную generated карту кода. Это увеличивало latency и объём
контекста, но не гарантировало полноту продуктового анализа: например,
асимметрия create/delete для Branch, Group и Staff/Teacher lifecycle долго
оставалась незамеченной.

В репозитории уже есть живой production-код, тесты, release evidence и RepoWise
с graph, symbol, risk, health, decisions и dead-code инструментами.

## Решение

DECISION: RepoWise является единственным активным code-intelligence и
agent-navigation слоем MagicMusicCRM.

1. Агент начинает с короткого `AGENTS.md` и использует RepoWise точечно по
   вопросу, а не проходит обязательные фазы.
2. Живой код/runtime/evidence остаются источником истины; low-confidence или
   mock retrieval проверяется по исходнику.
3. Продуктовые инварианты и текущие решения хранятся в обычных коротких
   документах, а не в versioned process package.
4. Небольшая правка не требует task ID, отдельного PRD, WBS или служебного
   отчёта.
5. Перед широкими/опасными изменениями используются RepoWise risk/context и
   релевантные tests; production safety gates сохраняются.
6. RepoWise index является generated local state и не коммитится. RepoWise не
   генерирует `AGENTS.md`.

## Последствия

Положительные:

- меньше обязательного контекста и ручной синхронизации;
- актуальный dependency graph строится из checkout;
- анализ концентрируется на пользовательском lifecycle и реальном runtime;
- архитектурные решения остаются доступными RepoWise.

Ограничения:

- RepoWise с mock embedder не заменяет прямую проверку source;
- runtime/dynamic dispatch может давать false-positive dead code;
- крупные финансовые, access и production изменения по-прежнему требуют
  усиленной проверки, backup и rollback.

## Проверка решения

- в текущем tree отсутствуют старые process rules и generated code maps;
- `repowise doctor` проходит;
- удалённый legacy path не находится в RepoWise;
- этот ADR отображается в `repowise decision list`;
- `AGENTS.md` не требует фазового workflow или task ledger.
