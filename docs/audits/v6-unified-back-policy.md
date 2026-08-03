# V6-203 — Unified UI / system / predictive Back

**Дата:** 2026-08-04
**Статус:** PASS

## Единый контракт

- `AppBackScope` использует ahead-of-time `PopScope.canPop`: локальная история объявляется до начала Android gesture и не теряет состояние.
- Native Navigator сохраняет порядок `dialog/sheet → pushed route → local tab state → system exit`; дополнительный navigator stack не создан.
- `AppBackButton` сначала закрывает текущий Navigator route, затем использует историю активной desktop-вкладки.
- Messenger и mobile context stack используют один scope; mobile chat header — одну подписанную UI Back action.
- Закрытие in-app deep link теперь возвращает на исходный экран. Role home используется только для холодной внешней ссылки без предыдущего route, поэтому карточка больше не отправляет пользователя молча на главную.

## Android API 35

На `MagicMusicCRM_API35` выполнены реальные edge Back gestures через ADB, не только framework callback:

1. partial `MagicSheet` закрыт, root сохранён;
2. nested dialog закрыт первым, full sheet остался открыт;
3. full sheet закрыт следующим gesture;
4. pushed route вернулся к source;
5. root local state был поглощён без выхода из приложения.

Integration test: 1/1 PASS. Crash buffer, `E/flutter`, `RenderFlex overflowed`, `FATAL EXCEPTION` — 0.

## Проверки

```text
flutter analyze
PASS — No issues found

flutter test test/core/navigation/app_back_policy_test.dart
PASS — 4/4

targeted navigation/workspace/sheet/messenger/profile regression
PASS — 37/37

flutter test integration_test/v6_back_device_test.dart -d emulator-5554
PASS — 1/1 (Android API 35, real edge gestures)

scripts/v6_ux_inventory.ps1 -Check
PASS — unowned=0, legacy WillPopScope=0

git diff --exit-code -- docs/audits/v6-wire-service-baseline.{json,md}
PASS — exact wire baseline unchanged

git diff -- server
PASS — empty
```
