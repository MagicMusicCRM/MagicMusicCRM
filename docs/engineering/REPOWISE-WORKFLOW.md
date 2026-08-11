# RepoWise-first workflow

RepoWise используется для сокращения времени поиска, а не как новый фазовый
процесс. Для обычной задачи достаточно понять область, оценить риск, изменить
код и проверить результат.

## Как выбирать инструмент

| Задача | RepoWise |
|---|---|
| Первый вход в незнакомый репозиторий | `get_overview` один раз |
| «Как работает / где находится / почему» | `get_answer` |
| Найти все совпадения, symbol или path | `search_codebase` |
| Понять связи файла/модуля | `get_context` |
| Прочитать точное тело symbol | `get_symbol` |
| Оценить файл до широкой правки | `get_risk` |
| Выбрать hotspot для рефакторинга | `get_health` |
| Найти cleanup-кандидаты | `get_dead_code` |
| Проверить commit/range перед merge | `get_change_risk` |
| Найти rationale решения | `get_why`; при сбое — current decisions и git |

`get_answer` не нужно предварять отдельным search. Search нужен, когда требуются
сырые ранжированные совпадения или полный список.

## Доверие к ответу

- `high confidence` с живыми citations можно использовать напрямую.
- `medium/low confidence` перепроверяется через `get_symbol` или `rg`.
- При `embedder=mock` или `semantic_search=false` RepoWise остаётся полезным
  для graph/symbol/risk/health, но концептуальный поиск обязательно сверяется с
  исходником.
- Runtime behavior и production evidence сильнее любого сгенерированного
  описания.

## Перед изменением

Для локальной очевидной правки достаточно контекста затронутого файла. Для
изменения контракта, shared service, RBAC, finance, lessons, migrations или
release tooling:

1. запросить `get_context`;
2. запросить `get_risk`;
3. проверить `docs/architecture/CURRENT-DECISIONS.md`;
4. прочитать конкретные callers/tests, названные результатом.

Не создавать отдельный PRD, backlog, WBS или отчёт, если пользователь этого не
просил и изменение не вводит новое продуктовое правило.

## После изменения

1. Запустить минимальный релевантный тест.
2. Проверить `git diff --check` и чужие изменения.
3. После структурной правки выполнить:

   ```powershell
   repowise update --index-only
   ```

4. Перед merge существенного кода использовать `get_change_risk`.
5. Новое долговечное решение записать в
   `docs/architecture/CURRENT-DECISIONS.md` или отдельный ADR с явной строкой
   `DECISION: ...`.

## Настройка

Индекс RepoWise является локальным generated state и не коммитится. RepoWise
не должен автоматически генерировать или перезаписывать `AGENTS.md`.

Новая машина:

```powershell
repowise init --no-prose --no-agents --no-claude-md --codex --no-editor-setup
repowise doctor
```

Обновление CLI выполняется отдельно от application dependencies и всегда
проверяется через `repowise --version` и `repowise doctor`.
