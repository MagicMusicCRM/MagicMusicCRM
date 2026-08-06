# Этап 8 — системный UX/UI-проход

**Дата:** 2026-08-06
**Статус:** ENGINEERING PASS
**Граница:** Flutter UI; новых изменений API, БД и `server/` на этапе 8 нет.

## Что исправлено

- Фильтры расписания, фильтры задач, выбор ученика и действия сообщения
  переведены с локальных `showModalBottomSheet` на общие v7 adaptive
  sheet/drawer surfaces. Прямых production-вызовов bottom sheet вне
  `magic_sheet.dart` осталось `0`.
- Длинный редактор доступа открывается полноэкранным маршрутом и закрывается
  системным Back без пустой 10%-области.
- Устранён реальный overflow календаря месяца на ширине 360 px: compact badge
  пробного урока адаптируется к ширине ячейки и сохраняет semantic label.
- Добавлены labels для icon-only FAB заметки и перехода к новым сообщениям.
  Статические гейты подтверждают `0` IconButton и `0` icon-only FAB без label.
- Аналитика проверяется на 360/600/840/1000/1200 px при 200% text scale;
  общая visual baseline теперь включает все пять контрольных ширин.
- Сохранён один основной create action на viewport: расписание, задачи и
  аналитика не получили дублирующих header/FAB действий.

## Состояния и платформенные контракты

- loading/empty/error/forbidden/retry остаются на принятых v7 primitives;
  route inventory фиксирует state gaps `0`.
- Windows mouse wheel и Shift+wheel проходят через owned scroll controllers и
  видимый desktop scrollbar.
- Android использует full-width expandable sheet; длинная форма доступа —
  fullscreen route. App/system Back проверен в порядке overlay → dialog →
  route → dirty-form decision → local history.

## Машинные inventories

```text
routes=22
production-reachable Dart files=251
production screens=22/22
state gaps=0
surface/navigation/input unowned=0
production scroll sites=145
explicit scrollbar callsites=12
production Back/exit sites=191
predictive Back sites=40
legacy WillPopScope sites=0
```

`scripts/v6_ux_inventory.ps1 -Check` — PASS; wire/service baseline обновлён без
изменения контрактов.

## Проверки

```text
flutter analyze: PASS, 0 issues
Stage 8 targeted UX suite: 36/36 PASS
Flutter full suite: 606/606 PASS
Windows desktop scroll integration: 1/1 PASS
Android 15 API 35 expandable sheet integration: 1/1 PASS
Android 15 API 35 system Back integration: 1/1 PASS (V6_BACK_DEVICE_PASS)
git diff --check: PASS
```

## Ограничение статуса

Это инженерная приёмка, не OWNER UAT. Реальные аккаунты пяти ролей,
раздельный Windows/Android сценарный UAT, release-сборки и выпуск относятся к
этапу 9; они здесь не объявляются выполненными.
