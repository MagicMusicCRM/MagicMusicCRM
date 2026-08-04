# V6-301 — Explicit desktop scrollbar ownership

**Дата:** 2026-08-04
**Статус:** PASS

## Принятый инкремент

- `MagicDesktopScrollbar` создаёт или принимает ровно один `ScrollController`, передаёт его одному scrollable owner и показывает interactive thumb/track только на desktop (и wide web от 840 px).
- Global `ScrollbarThemeData` отвечает только за внешний вид; автоматическое владение и вложенные primary-controller связи не добавлялись.
- На Android/iOS persistent scrollbar отсутствует, touch scroll остаётся нативным.

| Surface owner | Production owner |
|---|---|
| Page | Reports overview |
| Table/list | Finance payments |
| Board | Leads/Students horizontal board |
| Nested section | Leads/Students vertical columns + Group detail |
| Calendar | Schedule body vertical + horizontal; header/gutter остаются slave-sync |
| Tab strip | Desktop workspace tabs |

## Gate

```text
flutter analyze
PASS — No issues found

test/core/widgets/magic_desktop_scrollbar_test.dart
PASS — 3/3: Windows mouse thumb vertical/horizontal start→end,
       one attached position, Android persistent bar absent

Affected screen regressions
PASS — 18/18: workspace tabs, schedule drag/canvas, Leads,
       Finance roles and Reports persistence

integration_test/v6_desktop_scroll_device_test.dart -d windows
PASS — 1/1, both owned axes traverse, Flutter exception=0

flutter test
PASS — 526/526

pwsh scripts/v6_ux_inventory.ps1 -Check
PASS — routes=21, reachable=259, workspaceProduction=2, unowned=0,
       explicit scrollbar callsites=13

git diff -- docs/audits/v6-wire-service-baseline.{json,md}
PASS — empty, API/service baseline unchanged

git diff -- server
PASS — empty
```

Production approval не подразумевается: wheel/Shift+wheel/nested desktop policy закрывается в `V6-302`, общий desktop/UI gate — в `INT-S3`.
