# MagicMusicCRM Windows UX/UI Audit

Дата: 2026-06-16
Поверхность: локальный Windows runner `build/windows/x64/runner/Release/magic_music_crm.exe`
Роль: управляющий, авторизованная сессия
Viewport: 1267 x 714, desktop dark theme
Метод: ручной проход через Computer Use, screenshots-first, без разрушительных действий

## Scope

Проверены основные разделы shell:

1. Чат: список, открытие диалога, поиск.
2. Обзор: KPI, alert-блок, переходная логика.
3. Расписание: загрузка/пустой экран.
4. Лиды: канбан, карточка лида, колонки, overflow-меню.
5. Пользователи: поиск, фильтры ролей, dropdown смены роли.
6. Финансы: список платежей, period toggle, создание платежа.
7. Задачи: фильтры, список, overflow-меню, FAB создания.
8. Отчёты: аналитика, финансы, активность.

Не выполнялись реальные удаления, смена ролей, отправка сообщений, создание платежей/задач и другие действия, которые могли бы изменить данные. Accessibility оценена по видимой UI-структуре; полноценная проверка screen reader/keyboard traversal не подтверждена, потому что Computer Use не вернул accessibility tree для Flutter window.

## Evidence Index

Скриншоты лежат в `screenshots/`.

| Step | File | Health |
|---:|---|---|
| 1 | `01-reports-activity-log.jpg` | Problematic |
| 2 | `02-reports-analytics.jpg` | Needs polish |
| 3 | `03-reports-finance-tab.jpg` | Acceptable |
| 4 | `04-chat-list-empty-selection.jpg` | Mostly healthy |
| 5 | `05-chat-open-thread.jpg` | Mostly healthy |
| 6 | `06-chat-search-no-results.jpg` | Inconclusive input test |
| 7 | `07-chat-search-cleared.jpg` | Inconclusive input test |
| 8 | `08-chat-search-direct-type.jpg` | Inconclusive input test |
| 9 | `09-overview-dashboard.jpg` | Useful but overloaded |
| 10 | `10-schedule-board.jpg` | Broken state |
| 11 | `11-leads-pipeline.jpg` | Dense, functional, clipped |
| 12 | `12-users-roles.jpg` | Risky control model |
| 13 | `13-finance-payments.jpg` | Mostly healthy |
| 14 | `14-tasks-list.jpg` | CTA risk |
| 15 | `15-reports-analytics-return.jpg` | Needs polish |
| 16 | `16-schedule-after-long-wait.jpg` | Broken state confirmed |
| 17 | `17-lead-card-open.jpg` | Dense form risk |
| 18 | `18-leads-columns-action.jpg` | Broken/blank modal |
| 19 | `19-users-role-dropdown.jpg` | Risky action affordance |
| 20 | `20-finance-add-payment-dialog.jpg` | Needs form guidance |
| 21 | `21-task-create-dialog.jpg` | Did not open dialog |
| 22 | `22-task-create-dialog-retry.jpg` | Did not open dialog |
| 23 | `23-task-item-menu.jpg` | Mostly healthy, needs safeguards |
| 24 | `24-leads-return-verified.jpg` | Navigation verified |
| 25 | `25-lead-card-overflow-menu.jpg` | Powerful hidden actions |
| 26 | `26-task-fab-after-long-wait.jpg` | CTA failure confirmed |

## Executive Summary

The app has a strong foundation for a desktop CRM: persistent left navigation, dense operational screens, good use of dark surfaces, and a clear gold brand direction. The strongest parts are the finance list, the lead board data density, and the manager overview's ability to show urgent operational numbers quickly.

The main release risks are not cosmetic. They are state communication and action feedback:

1. Schedule can render as an unlabeled blank grid for more than 7 seconds.
2. Task creation FAB appears clickable but does not open a dialog even after a long wait.
3. Lead columns configuration opens a modal with a large empty gray body.
4. High-impact CRM actions are hidden in overflow menus without enough confirmation, current-state marking, or consequence explanation.
5. Several controls look like filters but actually perform account/status mutations.

Overall UX health: medium. Visual direction is coherent enough, but operational trust is weakened by silent failures and ambiguous state.

## Strengths

- The desktop NavigationRail is now much more usable than icon-only navigation because labels are always visible.
- The product fits the CRM use case better than a marketing-style UI: dense lists, filters, dashboards, and operational tables are prioritized.
- Finance has a clear first screen: total, period toggle, payments list, and a single obvious add action.
- Lead board supports real manager workflows: status columns, fast filters, card metadata, and direct card actions.
- The recent report chart polish moved the analytics screen closer to Flat Magic by removing the harsh orange gradient.

## Findings

### [P0] Schedule renders a permanent blank/skeleton grid

Evidence: `10-schedule-board.jpg`, `16-schedule-after-long-wait.jpg`

After entering Schedule, the screen shows a grid of dark rectangular blocks without title, date, time labels, loading indicator, empty state, or retry. The same state remains after an additional 7 seconds.

Impact: this is a critical trust failure. A manager cannot tell whether data is loading, the calendar is empty, API failed, or the screen is broken.

Code context: `ScheduleWidget._fetchAll()` catches errors with `debugPrint` and clears `_isLoading`, but does not store `_loadError` for the UI. This creates a silent failure path.

Recommendation:

- Add explicit `_loadError` and render an error state with retry.
- Keep header/date controls visible during loading.
- Use a real skeleton with labels, not anonymous blocks.
- If there are no lessons, show an empty state: "На выбранный период занятий нет" plus "Создать занятие".

### [P0] Task FAB does not open create flow or explain loading/failure

Evidence: `14-tasks-list.jpg`, `21-task-create-dialog.jpg`, `22-task-create-dialog-retry.jpg`, `26-task-fab-after-long-wait.jpg`

The task screen shows a prominent gold FAB. Clicking it produces no visible dialog, loading state, disabled state, toast, or error. After a 12-second wait the screen is unchanged.

Code context: `_createTask()` fetches profiles, students, leads, groups, and teachers before opening `_TaskDialog`. If any request is slow or fails, the button appears dead because the UI does not set a pending state or show failure feedback.

Recommendation:

- Open the dialog immediately and lazy-load select options inside it.
- Or set `_creatingTask = true`, disable FAB, and show a small progress label/toast.
- Catch prefetch errors and show "Не удалось подготовить форму задачи" with retry.
- Add an extended FAB label on desktop: "Новая задача".

### [P1] Lead columns modal opens with blank gray content

Evidence: `18-leads-columns-action.jpg`

The "Колонки" action opens a modal titled "Колонки воронки", but the body is a large light-gray block with no loading text, no list items, no empty message, and no explanation. The add button exists, but the current columns are invisible.

Impact: users will not know whether columns are loading, hidden, broken, or unavailable.

Recommendation:

- Replace the gray body with list skeletons while loading.
- Show existing columns with name, color, count, reorder handle, edit/delete actions.
- If no statuses exist, show an empty state and explain "Добавьте первую колонку".
- Keep surface color aligned with dark theme; the light-gray panel violates the rest of the visual system.

### [P1] Leads board is powerful but horizontally clipped and visually overloaded

Evidence: `11-leads-pipeline.jpg`, `24-leads-return-verified.jpg`

The board has many columns and dense cards, which fits CRM work, but the rightmost column is clipped by the viewport and there is no clear horizontal scroll cue, sticky column header behavior, or minimap. Important data may feel cut off rather than scrollable.

Recommendation:

- Add visible horizontal scroll affordance, gradient edge fade, or "drag to scroll" cursor.
- Keep column headers sticky during vertical scroll.
- Reduce card noise: phone, branch, teacher, tag, source, date, and menu all compete at the same weight.
- Make the lead name and next action the dominant visual elements.

### [P1] Lead overflow menu hides high-impact actions without enough context

Evidence: `25-lead-card-overflow-menu.jpg`

The menu contains status transitions and actions such as "Добавить комментарий", "Создать задачу", "Назначить пробный". It does not visibly mark current status, explain irreversible consequences, or group high-risk state transitions away from secondary actions.

Recommendation:

- Mark current status with a checkmark and disable selecting the current status.
- Separate "move status" actions from "create related item" actions.
- For status changes that trigger automation or notifications, show confirmation or undo.
- Use clearer copy: "Перевести в: Новый", "Перевести в: Контакт".

### [P1] Role dropdown feels like a filter but can mutate user permissions

Evidence: `12-users-roles.jpg`, `19-users-role-dropdown.jpg`

The users screen has filter chips for roles and a green role dropdown on every row. The row dropdown visually resembles a harmless status selector, but it is a permission-changing control. The menu shown for a client only offers "Клиент" and "Преподаватель", while the filters show more roles, creating a mismatch between available role filters and editable role options.

Recommendation:

- Treat role change as a high-risk action: confirmation dialog, actor audit preview, and success/error toast.
- Use explicit button copy: "Изменить роль", not only a role pill.
- Explain unavailable roles or hide impossible filters/actions consistently.
- Add "last changed by / date" or audit hint for permission changes.

### [P1] Activity log is too technical for a manager-facing Reports tab

Evidence: `01-reports-activity-log.jpg`

Rows are titled generically as "Действие" and expose raw-ish event names like `auth.session_rotated`, `auth.login_password`, `auth.session_issued`. This looks like backend audit telemetry, not business activity.

Impact: managers need to answer "what happened and should I care?", not parse system event names.

Recommendation:

- Split "Активность" into "Операционная активность" and "Системный аудит" if both are needed.
- Render human copy: "Вход выполнен", "Сессия обновлена".
- Group by object/person and add severity.
- Hide low-value auth noise by default; keep it searchable for admins/security.

### [P2] Reports analytics still has readability and chart semantics issues

Evidence: `02-reports-analytics.jpg`, `15-reports-analytics-return.jpg`

The chart is better after local fixes, but there are still issues:

- The zero month creates a horizontal line and label that reads like a broken bar.
- Legend labels are very small and low-contrast.
- The two lesson series rely heavily on close gold/brown tones.
- The top tabs have a thin underline but weak active-state contrast.

Recommendation:

- For zero values, render a clear 2px baseline marker and label "0", not a bar slot.
- Use direct labels or stronger pattern/opacity difference for planned vs completed.
- Increase legend size and spacing.
- Make active tab stronger: filled indicator, bolder label, or pill background.

### [P2] Overview has useful metrics but weak prioritization

Evidence: `09-overview-dashboard.jpg`

The overview screen communicates many KPIs quickly, but the cards have similar visual weight. "209 конфликтов расписания" is critical but looks like one of many cards. Chevrons appear on nearly every card, so scanability suffers.

Recommendation:

- Promote critical operational issues into a top alert with direct CTA: "Разобрать 209 конфликтов".
- Group KPIs by workflow: money, students, tasks, schedule.
- Use card hierarchy: critical alert, primary KPIs, secondary details.
- Avoid giving every card the same chevron affordance unless every card truly navigates.

### [P2] Finance form lacks recovery guidance for disabled submit

Evidence: `20-finance-add-payment-dialog.jpg`

The add payment dialog is compact and visually consistent, but the "Добавить" button is disabled without explaining which fields are required. The student selector and amount field rely on placeholder-like labels.

Recommendation:

- Mark required fields.
- Add helper text under empty required fields after first submit attempt.
- Keep the disabled state but add visible guidance: "Выберите ученика и сумму".
- Consider opening with keyboard focus on "Ученик".

### [P2] Chat interaction is mostly healthy but search/input verification was inconclusive

Evidence: `04-chat-list-empty-selection.jpg`, `05-chat-open-thread.jpg`, `06-chat-search-no-results.jpg`, `08-chat-search-direct-type.jpg`

The chat shell is well structured: list on the left, active conversation on the right, clear empty panel when no chat is selected. Long previews and smoke-test chats create visual noise but the layout itself is understandable.

Computer Use text injection did not visibly enter text into the search field even after focused click. Because this may be a limitation of input injection into Flutter Desktop, I am not marking it as confirmed app failure.

Recommendation:

- Add a visible clear button inside search once text exists.
- Ensure keyboard focus, Ctrl+A, Backspace, and typing work with real keyboard testing.
- Add "no results" empty state for search.
- Reduce smoke/test data prominence in non-dev environments.

### [P2] Global visual system is close but not fully coherent

Evidence: screenshots across all sections, plus code tokens in `lib/core/theme/app_theme.dart`

The stated product direction is Deep Charcoal and Sophisticated Gold, and the app mostly follows that visually. But code and UI still mix old naming and accents:

- `primaryPurple` aliases gold.
- Material theme still uses `accentBlue` in some navigation/input states.
- Some old purple/blue status colors and glow-like active halos remain.
- Some modals use off-theme surfaces, most visibly the gray lead-columns body.

Recommendation:

- Rename token aliases to semantic names: `brandPrimary`, `brandAccent`, `statusInfo`.
- Remove old purple/blue aliases from new UI.
- Define one desktop focus ring color, one selected-state color, and one danger/confirm language.
- Keep Flat Magic: matte surfaces, no decorative glow, restrained gold.

## Accessibility Risks

These are likely issues from screenshots, not a full WCAG certification:

- Small text/chips around 10-11px are common in leads, reports, tasks, and finance.
- Gold-on-dark and green-on-dark small labels may fail contrast depending on exact color pair.
- Status and priority often rely on color plus compact text; some color-only dots are used.
- Icon-only controls such as FAB, kebab menus, refresh, link, and search need accessible labels and focus states.
- Several modals/dropdowns need keyboard validation: focus trap, Escape behavior, return focus to trigger, tab order.
- Disabled buttons do not explain recovery path.
- Activity log exposes technical strings that may not be screen-reader friendly.

## Recommended Fix Order

1. Fix Schedule failure state: visible header, loading, empty, error with retry.
2. Fix Task FAB: immediate feedback, prefetch error handling, or open dialog before async selects.
3. Fix Lead columns modal: dark surface, loading/empty/list states.
4. Add safeguards and better copy for role/status mutations.
5. Improve lead board scroll affordance and card hierarchy.
6. Simplify activity log language for managers.
7. Clean up design tokens and remove old purple/blue naming/accents.
8. Run real keyboard/a11y pass: tab order, focus trap, screen reader labels, text scaling.

## Evidence Limits

- The audit used current screenshots from this run only.
- I did not execute destructive operations or submit real forms.
- I did not validate screen-reader output.
- Computer Use did not provide a usable accessibility tree for this Flutter Desktop window.
- Text input into Flutter fields via Computer Use was unreliable, so text-entry findings are treated cautiously.
- The audit covered desktop Windows at one viewport. Mobile and Android require separate evidence.
