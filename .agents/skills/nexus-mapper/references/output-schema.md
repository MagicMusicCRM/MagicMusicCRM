# Спецификация схем вывода (Output Schema)

> **Жесткое ограничение этапа EMIT**: Данный файл обязателен к прочтению перед записью любых файлов в `.nexus-map/`. Схемы основаны на реальном выводе скриптов и соответствуют текущей версии.

---

## raw/ast_nodes.json (вывод extract_ast.py)

### Верхнеуровневая структура
```json
{
  "languages": ["cpp", "python"],
  "stats": {
    "total_files": 101,
    "total_lines": 23184,
    "parse_errors": 0,
    "supported_file_counts": {"python": 101},
    "languages_with_structural_queries": ["python", "javascript"],
    "module_only_file_counts": {"vue": 12}
  },
  "warnings": [],
  "nodes": [...],
  "edges": [...]
}
```

### Типы узлов

**Module (Модуль)**
```json
{
  "id": "src.nexus.parser",
  "type": "Module",
  "label": "parser",
  "path": "src/nexus/parser.py",
  "lines": 320,
  "lang": "python"
}
```

**Class (Класс)**
```json
{
  "id": "src.nexus.parser.TreeSitterParser",
  "type": "Class",
  "label": "TreeSitterParser",
  "path": "src/nexus/parser.py",
  "parent": "src.nexus.parser",
  "start_line": 15,
  "end_line": 287
}
```

### Связи (Edges)
Типы: `contains` (содержит: модуль -> класс) / `imports` (импортирует).

---

## raw/git_stats.json (вывод git_detective.py)

```json
{
  "analysis_period_days": 90,
  "stats": {
    "total_commits": 42,
    "total_authors": 1
  },
  "hotspots": [
    {"path": "src/tasks.py", "changes": 21, "risk": "high"}
  ],
  "coupling_pairs": [
    {"file_a": "...", "file_b": "...", "co_changes": 5, "coupling_score": 0.71}
  ]
}
```
**Уровни риска**: `changes < 5` (low), `5–15` (medium), `> 15` (high).

---

## Метаданные Markdown файлов

Каждый сгенерированный `.md` файл (`INDEX.md`, `arch/*.md` и т.д.) должен содержать заголовок:
```markdown
> generated_by: nexus-mapper v2
> verified_at: 2026-03-07
> provenance: AST-backed except where explicitly marked inferred
```

---

## concepts/concept_model.json (V1)

```json
{
  "$schema": "nexus-mapper/concept-model/v1",
  "generated_at": "2026-03-05T15:00:00Z",
  "repo_path": "/path/to/repo",
  "nodes": [
    {
      "id": "nexus.ast-extractor",
      "type": "System",
      "label": "AST Extractor",
      "responsibility": "Извлечение модулей/классов/функций через Tree-sitter",
      "implementation_status": "implemented",
      "code_path": "src/nexus/weaving/",
      "tech_stack": ["tree-sitter", "python"],
      "complexity": "medium"
    }
  ]
}
```

### Статусы реализации
- `implemented`: Код существует в репозитории (`code_path` обязателен).
- `planned`: Запланировано, но кода еще нет (`evidence_path` и `evidence_gap` обязательны).
- `inferred`: Предполагаемая структура на основе анализа дерева файлов.

---

## Валидация узлов

| Поле | Обязательность | Ошибка `[!ERROR]` |
|---|:---:|---|
| `id` | Да | Дубликат; наличие заглавных букв или пробелов (только kebab-case). |
| `type` | Да | Не входит в: System / Domain / Module / Class / Function. |
| `implementation_status` | Да | Не входит в: implemented / planned / inferred. |
| `code_path` | При implemented | Пустой путь или путь не существует в репо. |
