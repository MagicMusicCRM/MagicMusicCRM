# V6-205 — Representative adaptive modal set

**Дата:** 2026-08-04  
**Статус:** PASS

## Миграция

- Lesson quick view использует `AppSurfaceKind.quickView`: полноширинный expandable `MagicSheet` на compact и `MagicDrawer` на desktop. Старый самостоятельный bottom-sheet chrome удалён.
- Длинная create/edit Lesson form открывается отдельным fullscreen route с явной UI Back, полным рабочим пространством и закреплёнными actions вместо fixed-width modal entry point.
- Общий `SearchableSelect.show` использует `AppSurfaceKind.selection`: sheet на compact и drawer на desktop; встроенный selector больше не дублирует grabber/header контейнера.
- Удаление Lesson использует `AppSurfaceKind.confirmation`, остаётся коротким недисмиссируемым решением с отдельным destructive action.
- Существующие Lesson/ClientRef/Teacher/Room API вызовы, conflict preview, expectedVersion и payload не изменены; create/edit regression подтверждает ровно одну mutation на действие.

## Визуальная проверка

Android screenshot на 390×844 проверен по утверждённым v7-токенам и shared-компонентам: safe-width, `AppRadius.sheet`, `AppColor.surface/divider/gold/danger/actionBlue`, видимый grabber и `Развернуть`, одна основная кнопка, отделённое destructive-действие. Cropping, плохие отступы, неверные радиусы, `RenderFlex overflowed` — 0.

## Проверки

```text
flutter analyze
PASS — No issues found

representative modal + Lesson form + selector + adaptive policy
PASS — 16/16

flutter test
PASS — 522/522

flutter test integration_test/v6_modal_device_test.dart -d emulator-5554
PASS — 1/1, Android API 35

flutter test integration_test/v6_modal_device_test.dart -d windows
PASS — 1/1, Windows debug application

scripts/v6_ux_inventory.ps1 -Check
PASS — routes=21, reachable=258, workspaceProduction=2, unowned=0;
       reachable modal callsites 104 → 103, production scroll sites 143 → 142

git diff -- docs/audits/v6-wire-service-baseline.{json,md}
PASS — empty, API/service baseline unchanged

git diff -- server
PASS — empty
```
