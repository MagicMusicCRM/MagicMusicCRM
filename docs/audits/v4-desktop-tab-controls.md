# T1.2.6 — Desktop tab controls

- Hover `⋯` открывает Duplicate/Open new, Close и Close others.
- Linked entity поддерживает явное открытие в новой вкладке.
- Горизонтальная tab strip поддерживает drag-and-drop reorder; binding сохраняет новый порядок.
- Лимит 10 вкладок возвращает явный limit callback.
- Dirty close требует Save / Discard / Cancel; Cancel и ошибка Save не удаляют вкладку.

## Проверка

- `flutter test test/features/v4/desktop_tab_controls_test.dart` — 4/4 PASS.
- Targeted Flutter analyze — PASS.
