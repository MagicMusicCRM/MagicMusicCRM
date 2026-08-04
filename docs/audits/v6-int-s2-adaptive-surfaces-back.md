# INT-S2 — Adaptive surfaces & Back gate

**Дата:** 2026-08-04  
**Статус:** PASS

## Принятый инкремент

- `V6-201..205` закрыты: job-based adaptive surface policy, expandable mobile sheet, unified UI/system/predictive Back, dirty-form exit contract и representative Lesson/selector/confirmation migration работают через shared production components.
- Compact layouts проверены на 360/600/839 px, граница desktop — на 840 px; portrait/landscape, keyboard inset, SafeArea и sticky action покрыты отдельно.
- Android порядок подтверждён реальными edge gestures: keyboard → nested dialog → partial/full sheet → route → dirty decision → local state.
- CH-02 закрыт: primary route не строит duplicate content, wire-to-service diff пуст, Lesson `_saving` guard и double-click regression дают ровно одну mutation.
- CH-03 закрыт: ahead-of-time `PopScope`, один Save/Discard/Cancel contract и device matrix не позволяют system Back потерять ввод.

## Gate

```text
flutter analyze
PASS — No issues found

S2 targeted adaptive/sheet/Back/dirty/Lesson/subscription suite
PASS — 29/29

flutter test
PASS — 523/523

Android API 35:
- v6_expandable_sheet_device_test.dart  PASS 1/1
- v6_back_device_test.dart              PASS 1/1, real ADB edge gestures
- v6_modal_device_test.dart             PASS 1/1
- relevant logcat crashes/errors        0

Windows:
- v6_modal_device_test.dart             PASS 1/1

scripts/v6_ux_inventory.ps1 -Check
PASS — routes=21, reachable=258, workspaceProduction=2, unowned=0,
       legacy WillPopScope=0

git diff -- docs/audits/v6-wire-service-baseline.{json,md}
PASS — empty, API/service baseline unchanged

git diff -- server
PASS — empty
```

Production approval не подразумевается: real-account UAT и release/security gate остаются в `INT-S7`.
