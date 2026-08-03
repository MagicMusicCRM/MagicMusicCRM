# V6-204 — Единый контракт выхода из формы

**Дата:** 2026-08-04  
**Статус:** PASS

## Контракт

- `DirtyFormExitScope` и `DirtyFormExitController` дают один диалог `Сохранить / Не сохранять / Остаться` для UI Back и Android system/predictive Back.
- Desktop workspace использует то же решение для breadcrumb/Back, смены и закрытия вкладки; logout проверяет активную dirty-форму до очистки account-scoped workspace.
- `Остаться` не меняет форму. `Сохранить` ждёт успешный mutation и закрывает поверхность только после успеха. `Не сохранять` явно очищает draft/conflict.
- При сетевой ошибке или version conflict сохраняются field/server error, draft, `expectedVersion`, conflict и исходный idempotency key; повтор использует тот же mutation identity.
- На общий контракт переведены три production-формы карточки клиента: выдача, отмена и замена абонемента.

## Android API 35

На `MagicMusicCRM_API35` реальными edge-жестами подтверждён порядок keyboard → dirty decision → route. Первый выбор `Остаться` сохранил введённое значение и текущий route, второй `Не сохранять` закрыл форму. Существующая overlay/route/local-history матрица также осталась зелёной. `FATAL EXCEPTION`, `E/flutter` и относящиеся к приложению ошибки logcat — 0.

## Проверки

```text
flutter analyze
PASS — No issues found

dirty contract + three forms + workspace/navigation regression
PASS — 40/40

flutter test
PASS — 520/520

flutter test integration_test/v6_back_device_test.dart -d emulator-5554
PASS — 1/1 (Android API 35, real edge gestures)

scripts/v6_ux_inventory.ps1 -Check
PASS — routes=21, reachable=258, workspaceProduction=2, unowned=0,
       ahead-of-time Back=38, legacy WillPopScope=0

git diff -- docs/audits/v6-wire-service-baseline.{json,md}
PASS — empty, API/service baseline unchanged

git diff -- server
PASS — empty
```
