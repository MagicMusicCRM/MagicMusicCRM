# V6-302 — Desktop wheel and nested-scroll policy

**Дата:** 2026-08-04
**Статус:** PASS

## Единая policy

| Input | Owner |
|---|---|
| Wheel | Ближайший vertical owner; на его границе событие получает vertical parent |
| Shift+wheel | Ближайший horizontal board/calendar/tab owner |
| Native horizontal wheel | Ближайший horizontal owner |
| Thumb drag | Явный owner соответствующей оси из V6-301 |

Используется штатный Flutter `ScrollBehavior.pointerAxisModifiers`, поэтому дополнительный pointer-event layer не создан. Он уже разворачивает ось только для физической мыши и через `PointerSignalResolver` отдаёт событие первому owner, который действительно может прокрутиться.

Для узкой desktop-полосы вкладок добавлены подписанные стрелки «Прокрутить вкладки влево/вправо»; draggable horizontal thumb остаётся доступен.

## Gate

```text
nested wheel/controller widget scenario
PASS — wheel: column only; Shift+wheel: board only;
       column at end: parent page only; controller exception=0

desktop tab overflow scenario, width=500 px
PASS — right/left arrows traverse overflow and return to origin

integration_test/v6_desktop_scroll_device_test.dart -d windows
PASS — physical mouse wheel + Shift+wheel, wide Windows viewport, exception=0

targeted scrollbar + workspace suite
PASS — 11/11

flutter analyze
PASS — No issues found

flutter test
PASS — 528/528

pwsh scripts/v6_ux_inventory.ps1 -Check
PASS — routes=21, reachable=259, workspaceProduction=2, unowned=0

git diff -- server
PASS — empty
```

CH-05 закрыт: blanket wrapper и multi-attach отсутствуют, nested ownership и edge handoff проверены. Production approval остаётся за `INT-S7`.
