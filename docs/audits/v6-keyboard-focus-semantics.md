# V6-303 — Keyboard, focus, tooltip and semantics pass

**Дата:** 2026-08-04
**Статус:** PASS

## Результат

- Все 91 production `IconButton` имеют явный русский `tooltip`; исправлены 22 неподписанных действия.
- Tooltip одновременно даёт hover-пояснение и semantic tooltip; Material сохраняет штатный focus ring и активацию Enter/Space.
- Workspace overflow arrows, Back/Forward и остальные icon actions имеют конкретные, а не универсальные подписи.
- Escape/system Back использует принятый dirty-form Save/Discard/Cancel contract и не теряет ввод.

## Gate

```text
accessibility_inventory_test.dart
PASS — 2/2: production IconButton tooltip gaps=0,
       semantic tooltip + focused Enter activation

dirty_form_exit_test.dart
PASS — 4/4: Escape/Back cannot silently discard dirty or busy input

Windows target accessibility suite
PASS — 2/2

flutter analyze
PASS — No issues found

flutter test
PASS — 530/530

git diff -- server
PASS — empty
```

Production screen-reader acceptance остаётся частью role/device UAT в `V6-604` и `INT-S7`.
