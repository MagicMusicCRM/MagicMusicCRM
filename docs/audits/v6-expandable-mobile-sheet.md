# V6-202 — Full-width expandable mobile sheet

**Дата:** 2026-08-04  
**Статус:** PASS

## Реализация

- Compact `MagicSheet` использует один native `DraggableScrollableSheet`, существующий body и один переданный `ScrollController`.
- Поддержаны snap-состояния `0.58 / 0.90 / 1.00`, видимый drag handle и подписанное действие `Развернуть` / `Свернуть`.
- Full-width frame учитывает `SafeArea` и keyboard inset; body прокручивается независимо от закреплённого footer action.
- `Semantics.liveRegion` объявляет `частично развернуто` / `развернуто`; desktop-контейнер сохранил прежнюю ширину и поведение.
- Service/provider/DTO вызовы не изменены.

## Android API 35

Production `showMagicSheet` проверен на `MagicMusicCRM_API35` (`emulator-5554`):

- portrait long content: drag/button раскрывают окно до полного экрана;
- UI Automator видит sheet state `Окно «Оплата ученика»: развернуто`, кнопку `Свернуть`, scroll body, поле и закреплённую кнопку `Сохранить`;
- клавиатура открыта через реальный tap по координатам из UI tree; финальное действие остаётся доступно;
- crash buffer, `E/flutter`, `RenderFlex overflowed`, `FATAL EXCEPTION` — 0;
- integration test — 1/1 PASS.

Снимок устройства: [v6-expandable-sheet-api35.png](v6-expandable-sheet-api35.png)

## Проверки

```text
flutter analyze
PASS — No issues found

flutter test test/core/widgets/expandable_magic_sheet_test.dart ...
PASS — 23/23

flutter test integration_test/v6_expandable_sheet_device_test.dart -d emulator-5554
PASS — 1/1 (Android API 35)

scripts/v6_ux_inventory.ps1 -Check
PASS — routes=21, reachable=256, workspaceProduction=2, unowned=0

git diff --exit-code -- docs/audits/v6-wire-service-baseline.{json,md}
PASS — exact wire baseline unchanged

git diff -- server
PASS — empty
```

Widget matrix покрывает portrait/landscape, long/short content, все три snap-состояния, keyboard inset, доступность последнего поля и sticky action.
