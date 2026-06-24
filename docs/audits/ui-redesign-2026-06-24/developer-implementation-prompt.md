# Prompt for Developer Agent - Implement Leads to Students DnD Flow and Rebuild Apps

Ты работаешь в проекте:

`C:\Projects\MagicMusicCRM`

Перед началом обязательно прочитай:

1. `AGENTS.md`
2. `.anws/v3/05_TASKS.md`
3. `docs/audits/ui-redesign-2026-06-24/report.md`
4. Все визуальные примеры из `docs/audits/ui-redesign-2026-06-24/`

## Главная задача

Реализовать новый drag-and-drop flow переноса карточки клиента из канбана `Лиды` во вкладку `Ученики`, далее в нужный филиал и нужную колонку канбана выбранного филиала.

Это фронтовая задача. Backend/API контракты менять нельзя. `git diff -- server/` должен быть пустым.

## Визуальные примеры

Используй эти изображения как UX specification:

1. `docs/audits/ui-redesign-2026-06-24/dnd-flow-01.png`
   - Статичный канбан лидов.
   - Drag еще не начался.
   - Вкладки `Лиды / Ученики` компактные.

2. `docs/audits/ui-redesign-2026-06-24/dnd-flow-02.png`
   - Drag начался.
   - Карточка клиента в руках.
   - Верхние вкладки `Лиды / Ученики` расширяются.
   - `Ученики` получает dashed outline как явная drop-зона.

3. `docs/audits/ui-redesign-2026-06-24/dnd-flow-03.png`
   - Карточка заведена в поле `Ученики`.
   - Запускается 2-секундный progress indicator подтверждения.
   - Пока индикатор не заполнен, переход не происходит.
   - Если карточку увести из зоны до окончания индикатора, действие отменяется без side effects.

4. `docs/audits/ui-redesign-2026-06-24/dnd-flow-04.png`
   - После подтверждения происходит переход во вкладку `Ученики`.
   - Та же карточка клиента остается в руках.
   - Вкладки `Лиды / Ученики` остаются раскрытыми.
   - Под ними раскрываются филиалы.
   - Под филиалами показывается канбан первого филиала из вкладки учеников.

5. `docs/audits/ui-redesign-2026-06-24/dnd-flow-05.png`
   - Пользователь переносит карточку на нужный филиал.
   - У филиала появляется такой же progress/acceptance indicator.
   - После подтверждения активного филиала канбан меняется на канбан этого филиала.
   - Карточка всё еще в руках.

6. `docs/audits/ui-redesign-2026-06-24/dnd-flow-06.png`
   - Карточка переносится в нужную колонку канбана выбранного филиала.
   - Целевая колонка подсвечена dashed outline.
   - Карточка еще не отпущена.

7. `docs/audits/ui-redesign-2026-06-24/dnd-flow-07.png`
   - Карточка отпущена.
   - Все расширенные поля свернуты.
   - Вкладка `Ученики` остается активной.
   - Выбранный филиал отображается как обычный фильтр/контрол.
   - Карточка ученика стоит в нужной колонке.
   - Показан success strip/toast с `Отменить`.

Дополнительные визуальные материалы:

- `docs/audits/ui-redesign-2026-06-24/01-palette.png`
- `docs/audits/ui-redesign-2026-06-24/06-all-sections-new-palette.png`
- `docs/audits/ui-redesign-2026-06-24/redesign-concept.html`
- `docs/audits/ui-redesign-2026-06-24/dnd-seven-step-flow.html`

## Recolor context

Палитра приложения уже была перенесена в общий theme layer. Проверь текущий diff и не откатывай его:

- `lib/core/theme/telegram_colors.dart`
- `lib/core/theme/design_tokens.dart`
- `lib/core/theme/app_theme.dart`
- `test/theme/design_tokens_test.dart`

Цветовая логика:

- Gold `#C9A85E` - бренд, активная навигация, редкие brand states.
- Action blue `#3B82F6` - рабочие primary-действия, focus, links, фильтры.
- Transfer cyan `#14B8A6` - переносы, конвертация `Лид -> Ученик`, transfer surfaces.
- Success green `#22C55E` - успешные операции.
- Warning amber `#F59E0B` - предупреждения.
- Danger red `#EF4444` - только ошибки, конфликты, просрочки.

Нужно сохранить реколор по всем разделам и не возвращать старую перегруженную черно-золотую схему.

## Likely implementation files

Начни с этих файлов:

- `lib/features/manager/presentation/widgets/clients_widget.dart`
- `lib/features/manager/presentation/widgets/leads_widget.dart`
- `lib/features/manager/presentation/widgets/students_board_widget.dart`
- `lib/features/manager/presentation/widgets/convert_lead_dialog.dart`
- `lib/core/theme/design_tokens.dart`
- `lib/core/theme/app_theme.dart`

Кодовые якоря:

- `lib/features/manager/presentation/widgets/leads_widget.dart`
  - `convertLeadToStudent(...)`
  - current/future DragTarget contract around the existing conversion flow
  - current `LongPressDraggable<String>` for lead cards

- `lib/features/manager/presentation/widgets/students_board_widget.dart`
  - current student board columns
  - current `LongPressDraggable<Map<String, dynamic>>`
  - branch/status board structure

## Implementation requirements

### 1. Desktop drag behavior

Desktop drag must not feel broken.

Implement visible drag affordance:

- visible drag handle on client cards;
- cursor/hover feedback if available;
- lifted ghost card while dragging;
- source placeholder where card was picked up;
- target dashed outlines;
- no silent no-op when user drags normally with mouse.

Long press may remain for touch if needed, but desktop should support normal pointer drag with a movement threshold.

### 2. Expanded top tabs

When a lead card drag starts:

- expand `Лиды / Ученики` top segmented control;
- keep current screen on Leads kanban;
- make `Лиды` a return/source zone;
- make `Ученики` a large drop zone with dashed outline;
- show clear label like `перенести сюда` / `подтверждение 2 сек.`;
- keep the card in hand.

### 3. Two-second transition confirmation

When dragged card enters `Ученики` target:

- start a 2-second progress indicator;
- visually fill indicator;
- do not convert or switch tab until timer completes;
- cancel timer if pointer leaves the target before completion;
- do not call backend or mutate data before the confirmation completes.

### 4. Switch to Students with same card in hand

After `Ученики` transition indicator completes:

- switch UI to `Ученики`;
- keep the same lead card in drag state;
- keep tabs expanded;
- reveal branch drop fields directly under the tabs;
- show the first branch's student kanban under the branch fields by default.

### 5. Branch selection with progress indicator

When card enters a branch target:

- start branch confirmation progress;
- cancel if pointer leaves before completion;
- after completion, mark branch selected;
- update board to that branch's student kanban;
- keep the card in hand.

### 6. Drop into target student column

On selected branch kanban:

- highlight valid target columns with dashed outline;
- allow dropping into a specific student status/column;
- after drop, call existing conversion flow in a way that preserves API contracts;
- set final branch/status/column correctly;
- show success strip/toast with undo.

### 7. Final collapsed state

After successful drop:

- collapse expanded tabs and branch fields;
- keep `Ученики` active;
- show selected branch as normal control/filter;
- render the new student card in the chosen column;
- show success strip/toast with `Отменить`.

## Data and API constraints

- Do not change backend contracts.
- Do not edit `server/`.
- Use existing service/API calls where possible.
- If the current backend does not support one needed final field directly, keep the flow frontend-safe and document the exact backend gap instead of inventing a contract.
- Preserve comments/history/source linkage from lead to student.
- Do not lose the original lead context during optimistic UI.

## UX constraints

- No hidden gesture-only critical path.
- Every pending state needs visible feedback.
- Every cancel path must leave data unchanged.
- Red is only for real errors.
- Use skeleton/progress, not blank screens.
- Keep old data visible during transitions/refetches.
- Do not use nested cards inside cards.
- Use 8px-ish cards and stable dimensions.
- Text must not overflow or overlap on desktop.

## Step-by-step plan for the developer agent

1. Read project context and inspect current DnD code.
2. Map current lead statuses, student branches, and student columns.
3. Identify how `convertLeadToStudent(...)` currently creates a student and what fields can be passed/updated.
4. Add a small internal DnD state model for:
   - idle;
   - dragging lead;
   - hovering `Ученики`;
   - confirmed students tab;
   - hovering branch;
   - branch confirmed;
   - hovering student column;
   - dropped/success.
5. Build expanded tabs UI state.
6. Build 2-second confirmation timer for `Ученики`.
7. Build branch strip/drop targets and branch timer.
8. Wire board switching while preserving the dragged card.
9. Wire final column drop to conversion/update logic.
10. Add fallback menu action `Перенести в ученики вручную`.
11. Add tests for state transitions where feasible.
12. Run verification.

## Required verification

Run at minimum:

```powershell
flutter analyze
flutter test test/theme/design_tokens_test.dart
flutter test
git diff -- server/
```

`git diff -- server/` must be empty.

## Required rebuilds

After implementation and tests, rebuild both desktop and Android artifacts.

Windows release:

```powershell
flutter build windows --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

Then recreate/update the distribution folder and zip under:

```text
C:\Projects\MagicMusicCRM\dist\
```

Android debug or release, depending on release target:

```powershell
flutter build apk --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

If AAB is required:

```powershell
flutter build appbundle --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

Record final artifact paths and hashes in the final response.

## Final response required from developer agent

Return:

- files changed;
- exact UX behavior implemented;
- screenshots or short visual evidence if available;
- tests run and results;
- Windows artifact path and hash;
- Android artifact path and hash;
- explicit statement that `server/` was not changed;
- any remaining backend/data limitation if discovered.
