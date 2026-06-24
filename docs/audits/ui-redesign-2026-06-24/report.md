# Magic Music CRM UI audit and redesign concept - 2026-06-24

## Scope

Read-only product audit for the current Windows manager build:

- Build path: `C:\Projects\MagicMusicCRM\dist\MagicMusicCRM-1.1.22-123-windows-x64\magic_music_crm.exe`
- Verified process path: same `C:\Projects\MagicMusicCRM\dist\...` build, not the old checkout under `C:\Users\potyl\Projects`
- Primary screen reviewed: manager `Клиенты`, tabs `Лиды` and `Ученики`
- App code was not changed. This folder contains visual audit artifacts and static concept images.

## Generated artifacts

- `01-palette.png` - theoretical palette and token usage
- `02-leads-to-students-dnd.png` - proposed Leads to Students drag-and-drop bridge
- `03-students-branch-drop.png` - proposed Students board by branch and column
- `04-visual-audit.png` - visual audit summary
- `05-tab-transfer-dnd-flow.png` - requested top-tab transfer DnD flow
- `06-all-sections-new-palette.png` - palette distribution across functional sections
- `07-refined-tab-branch-flow.png` - refined flow where branches open under tabs while the lead board stays visible
- `dnd-flow-01.png` ... `dnd-flow-07.png` - final seven-screen storyboard requested by owner
- `dnd-seven-step-flow.html` - source HTML for the final storyboard
- `schedule-flow-01.png` ... `schedule-flow-07.png` - schedule redesign storyboard requested by owner
- `schedule-redesign-flow.html` - source HTML for the schedule storyboard
- `redesign-concept.html` - source HTML used only for rendering the images

## Main findings

1. Drag and drop feels broken on desktop because both boards use `LongPressDraggable` with a 500 ms delay. A normal mouse drag has no obvious feedback, and the UI gives no visible instruction or drag handle.

2. Lead to student drag-and-drop is not implemented as an end-to-end UI flow. The code contains a future contract saying the Students board should call `convertLeadToStudent(...)`, but that target flow is not wired as a visible user path.

3. The current palette is too dependent on black, white outlines, gold, and bright blue. Borders, chips, tabs, buttons, and card outlines compete with each other, so the manager has to parse the screen instead of scanning it.

4. The Students board needs branch-first layout. A branch is a business decision, not just a filter. The proposed structure is: `Филиал -> Колонка ученика -> Карточка`.

5. Red should be reserved for real errors or conflicts. If room/teacher frames look red while conflicts are zero, the interface creates false alarm.

6. Test/smoke data in manager UI reduces trust. Technical leads and chats need a sandbox marker, environment filter, or removal from production-facing roles.

## Proposed DnD behavior

1. Start drag immediately after pointer movement threshold on desktop. Keep long press only for touch if needed.
2. Add visible drag handle on every movable card.
3. When a card is in hand, expand the top `Лиды / Ученики` segmented control into a large transfer target.
4. Holding the card over `Ученики` starts a 2-second confirmation timer with a filling progress indicator.
5. If the card leaves the `Ученики` target before the timer completes, cancel the transition without side effects.
6. After the timer completes, show the branch picker directly under the expanded `Лиды / Ученики` tabs, while the user is still on the Leads kanban.
7. Hovering a branch starts the same progress/acceptance pattern for branch selection.
8. Only after branch selection, open `Ученики / выбранный филиал` with that branch's vertical student kanban.
9. On final drop, open a short confirmation sheet with duplicate-phone check and optional fields: teacher, group, first lesson.
10. After success, show toast with `Отменить`.
11. Keep fallback action in the card menu: `Перенести в ученики вручную`.

## Final seven-screen storyboard

1. Static Leads kanban. Compact `Лиды / Ученики` tabs, no drag state.
2. Drag starts. Tabs expand into large drop fields with dashed outlines.
3. Card enters `Ученики`. Two-second progress confirmation runs, Leads kanban stays in the background.
4. Confirmation completes. The app switches to `Ученики`; the same card remains in hand. Branch fields open and the first branch kanban is shown.
5. Card is moved to the desired branch. Branch progress confirms selection, and the visible kanban changes to that branch.
6. Card is dragged over the target column in the selected branch kanban.
7. Card is released. All expanded fields collapse; the student card appears in the target column with an undo success strip.

## Implementation anchors

- Lead conversion entrypoint: `lib/features/manager/presentation/widgets/leads_widget.dart:575`
- Future DragTarget contract: `lib/features/manager/presentation/widgets/leads_widget.dart:572`
- Lead card drag delay: `lib/features/manager/presentation/widgets/leads_widget.dart:1691`
- Student card drag delay: `lib/features/manager/presentation/widgets/students_board_widget.dart:790`

## Palette recommendation

- App background: `#101114`
- Surface: `#181B20`
- Raised surface: `#20242B`
- Border: `#313741`
- Text: `#F1F3F5`
- Muted text: `#AAB2BF`
- Brand gold: `#C9A85E`
- Work action blue: `#3B82F6`
- Transfer cyan: `#14B8A6`
- Success: `#22C55E`
- Warning: `#F59E0B`
- Danger: `#EF4444`

Rule: gold is brand and rare primary accent, blue is normal work action, cyan is conversion/transfer, red is only real error.

## Palette rollout by section

- `Обзор`: gold for brand summary, blue for actionable drill-down.
- `Расписание`: blue for selection/booking, red only for real room/teacher conflicts.
- `Клиенты`: cyan for lead-to-student transfer, gold only for active tab/brand.
- `Чат`: gold outgoing/admin-brand bubble, quiet neutral incoming surfaces.
- `Пользователи`: violet for role/RBAC metadata, amber for warnings.
- `Финансы`: green for successful payments, amber for expected/debt states.
- `Задачи`: amber for due soon, red only for overdue/blocking tasks.
- `Отчеты`: blue/cyan/violet data series, no gold overuse in charts.

## Schedule redesign storyboard

Goal: make the day schedule behave like an administrator's working grid, not like a static calendar. The grid runs from `08:00` through the `23:00` row, ending at `00:00`, with rooms as columns and time as vertical rows.

Revision note: schedule images were widened to `1920px` and the day canvas now uses a repeated hourly grid across the full height. The free area must never look like one flat gray block; every hour/room intersection should remain readable as a cell.

Scroll revision: the time column is wider, room columns are narrower, and the internal schedule canvas may be wider and taller than the visible app viewport. Desktop and mobile must support both horizontal and vertical scrolling when the room count or day height requires it.

Drag revision: when an existing lesson is dragged vertically or horizontally, do not show dashed target blocks. Keep the original lesson highlighted in its source position until drop, and show the dragged lesson as the card in hand. If the card is held near the visible canvas edge, start autoscroll in that direction.

Mobile revision: on phones, keep the time column sticky on the left, room columns in a horizontal canvas, and the day grid vertically scrollable. Edge-autoscroll must work on left/right/top/bottom edges while a lesson card is in hand.

1. Static day view: empty cells stay clean. Repeated helper text is removed from the grid; all rules live in the legend above it.
2. Vertical selection: press and drag only inside one room column to choose several hours. Horizontal selection across rooms is visually rejected and does not create a multi-room booking.
3. Release after vertical selection: open a compact appointment form with room, start time, end time and duration already filled.
4. Move existing lesson vertically: dragging a lesson up or down changes only time, preserving student, teacher, room and lesson data. The source lesson remains highlighted until drop.
5. Resize by edge: top and bottom handles appear only on hover and change only start/end time. The user can shorten or extend a lesson without opening the lesson window.
6. Move existing lesson horizontally: horizontal drag is allowed only for an already existing lesson and changes only the room, preserving time, student and teacher. The source lesson remains highlighted until drop.
7. Single-cell click: one click on a free hour opens the quick create form with a default duration of `1 час`.

Design rule: blue marks booking and room moves, cyan marks active time selection, gold marks resize handles and existing brand-priority lessons, red is reserved for real conflicts or rejected gestures.
