# Prototype v6 — Complete Inventory
**File:** `docs/prototypes/crm-redesign-v6.html`
**Spec:** `docs/superpowers/specs/2026-06-20-crm-feedback-redesign.md`
**Audited:** 2026-06-21

---

## 1. Overview

Single self-contained HTML file (~2960 lines). Runs entirely in the browser with no network calls. Two device frames (Phone 390×844 / Desktop 1440×900) are rendered simultaneously; only one is visible at a time, toggled by a top control strip. Four roles are switchable via a second top toggle: Клиент, Преподаватель, Администратор, Управляющий. All state lives in a JS `ST` object; all data is in-memory mock arrays (`LEADS`, `STUDENTS`, `LESSONS`, `USERS`, `TASKS`, `EXPENSES`, etc.). The prototype gates the app behind a login screen (K2); logout returns to it. No real backend exists anywhere; every mutation is in-memory, every network-feel action is simulated with a toast + optimistic update.

Design tokens are locked: gold `#C5A059`, bg `#101012`, surface `#1A1A1D`, sidebar `#151518`, input `#242427`, divider `#2A2A2D`. SVG icons only, Inter font via Google Fonts (the one real external call).

---

## 2. Features — complete inventory

### Auth / Login screen (K2)
- Login screen rendered over the full frame before any app content is visible (`ST.authed = false` on boot).
- Login form: phone/email + password fields, pre-filled with demo credentials (`anna@magicmusic.ru` / `demo123`); submit validates non-empty, then calls `enterApp()`.
- Sign-up form: name + login + password; same non-empty check; success triggers toast "Аккаунт создан".
- Toggle between login/signup via "Создать аккаунт" / "Уже есть аккаунт?" links.
- "Войти как…" quick-role grid (2×2 buttons: Управляющий, Администратор, Преподаватель, Клиент) — one click logs in as that role with a toast confirming role.
- Logout from Profile (any role) calls `logout()` → returns to login screen, resets `ST.authed`.
- Auth error banner (`auth-err`) shown on empty-field submit; hidden by default.
- Both Phone and Desktop frames share the same auth state; both sync simultaneously.

### Top control strip (outside any frame)
- **Device toggle** (Телефон / Десктоп): switches rendered frame without re-seeding data.
- **Role toggle** (Клиент / Преподаватель / Администратор / Управляющий): clamps active nav to role-permitted tabs and re-renders everything; gold animated glide indicator.
- `data-role` and `data-frame` on `<html>` drive CSS RBAC and layout selectors app-wide.

### Navigation shell — Phone
- Bottom tab bar (`.tabbar`): shows up to 4 primary tabs + "Ещё" overflow for roles with more.
- "Ещё" opens a pop-menu listing overflow nav items (Финансы, Отчёты, Пользователи for manager).
- App-bar (`.appbar`) at top: title + subtitle + contextual action buttons per view.
- Back button visible when a sub-pane is open (chat conversation, etc.).

### Navigation shell — Desktop
- Left rail (`.rail`): 76px wide, shows all nav items for the role with icon + label + badge.
- Rail footer: avatar button opening profile pop-menu (Мой профиль / Уведомления / Выйти).
- Content area has its own header band with view title + subtitle.

### Per-role nav (ground truth from spec + prototype code)
| Role | Nav items |
|---|---|
| Управляющий | Чат · Расписание · Клиенты · Задачи · Отчёты · Пользователи · Настройки |
| Администратор | Чат · Расписание · Клиенты · Задачи |
| Преподаватель | Чат · Расписание · Ученики (own) |
| Клиент | Чат · Моя школа · Профиль |

RBAC enforcement:
- `html[data-role="admin"] [data-mgr]` — CSS hides manager-only elements for admins.
- `usersView()` returns an "Доступно только Управляющему" empty-state if role != manager.
- `settingsView()` similarly blocks non-managers.
- `data-pov="teacher"` or `"client"` on subtrees hides `.staff-phone` and `.call-link` elements via CSS.
- Teachers have no block-drag booking (`attachBlockSelect` returns early if role === 'teacher').
- Teacher card ⋯ menu shows only "Оставить комментарий" (K8).
- Client cannot add other students (K9; not explicitly blocked in JS, just absent from UI).

### Чат (Chat)
- Two-pane on desktop (chat list 340px + conversation); single pane swap on phone.
- Chat list: 6 mock chats (CHATS array) — leads, group, staff, student.
- Each list item: avatar (initials or group icon), online dot, name, timestamp, preview, unread badge, double-tick read indicator.
- Muted chat variant: unread count shown in gray.
- Live search bar filters chat list by name + message preview (K7 — full-width search, K1 — focused by appbar search icon).
- Skeleton loader (6 shimmer rows) shown for ~320ms on chat-pane open, then real items replace it (K14).
- Conversation view: date separators, incoming (dark) and outgoing (gold) bubbles.
- Consecutive messages from same sender: tighter border-radius (`.consec-in`/`.consec-out`).
- Voice message bubble: waveform visualization (22 sine-height bars), play button, duration label; clicking plays a toast (real playback not implemented — stub).
- Read receipts: single check vs double check icons in outgoing bubble meta.
- Composer: attachment button (toast stub), emoji button (toast stub), microphone button (toast stub), send button.
- Optimistic message send (K14): typing Enter or clicking send appends bubble immediately; read-tick upgrades from single to double after 700ms setTimeout.
- Call link in conversation header (phone only, non-group chats): `<a class="call-link" href="tel:...">` opens device dialer — real `tel:` link.
- Conversation ⋯ menu: "Сохранить как лида", "Открыть карточку", "Закрепить чат", "Очистить историю" (all toast/demo actions except open card which opens a real drawer).
- Desktop and phone frames maintain separate chat-pane state (`navPhone`/`navDesk` and `chatPane`).

### Клиенты (Clients) — Лиды kanban
- Segmented control: Лиды / Ученики (with counts).
- Persistent search bar (full-width) filters by name or normalized phone in real time.
- Filter drawer (slide-in from right): Филиал chips, Статус chips, Источник chips, Ответственный select. Chips toggle on/off (K1). "Показать 18" button closes drawer with toast.
- Columns editor drawer: rename column (inline input), delete column (trash), drag-to-reorder column rows (CC drag with insertion indicator). Works for both Воронка лидов (global) and per-branch student funnel. "Добавить колонку" appends a new column. Both drawers in Clients board and in Настройки share the same column editor (`CC_TARGET`/`CC_BRANCH`).
- 6 kanban columns (LEAD_STATUSES): Новый, Пробный урок, Звонок после пробного, Успешный, Отложенный, Отказ.
- 11 mock leads (LEADS array); lead card shows: initials avatar, name (truncated), phone (staff-only), status dot, tags (gold + plain), loss reason tag if status=lost.
- Card ⋯ menu (non-drag alternative): "Открыть карточку", "Указать причину потери", "Перенести в Ученики → [Тверская | Арбат | Сокол]" (explicit transfer via menu).
- Dropping into "Отказ" column auto-prompts for loss reason via pop-menu (LOSS_REASONS: Дорого, Нет времени, Локация, Другое).
- Loss reasons tracked in `ST.lossReasons` map and feed the "Причины потерь" funnel in Reports.

### Клиенты — in-kanban drag and drop
- Pointer-based drag with THRESH=6px threshold to distinguish tap from drag (E1 fix).
- Drag ghost (`.#dragGhost`): cloned card follows pointer at 1.03× scale, drop-shadow lift.
- G3 insertion line: golden 2.5px line painted at nearest card boundary within target column.
- G5 drop-arm: all columns get dashed gold border while a card is held.
- Releasing within a Лиды column: moves lead to that column (status change), re-renders kanban, shows toast.
- H7 dwell transfer: while holding, the "Лиды | Ученики" segmented control expands IN PLACE into dashed drop zones. The "Ученики" zone lights up gold when hovered. Dwell 350ms (with 10px jitter tolerance) fires `enterStudentTransfer()`.
- Student overlay (G4/G6): full-screen blurred overlay showing Филиал drop zones (big dashed cards). Dwell 350ms over a Филиал zone auto-reveals its discipline columns.
- Discipline columns (G6): each branch's disciplines + "Разноплановые" shown as kanban-style dashed zones with existing students shown at 50% opacity.
- Drop on a discipline zone: calls `doTransfer()`.
- Optimistic transfer (K6): card removed from LEADS, added to STUDENTS with `pending:true` immediately; "Переносится…" animated gold dot tag visible; `pending=false` after 900ms. Toast with "Отменить" rolls back the transfer.
- Rearm after branch drop: card stays "in hand" for the discipline stage (continuous gesture).

### Клиенты — Ученики board
- Branch selector (Филиал chips): filters board to one branch.
- Each branch has its own funnel columns (копия DISCIPLINES + Разноплановые), configurable independently in Настройки.
- 8 mock students (STUDENTS array); same card design as leads.
- Student card ⋯ menu: "Открыть карточку", "Сменить дисциплину" (toast), "Удалить" (toast).
- No drag-and-drop for student cards (click-only).

### Карточка клиента (Client card drawer)
- Unified for leads and students; open from kanban click, ⋯ menu, or Users jump-to-card.
- Header: avatar, name, phone (staff-only), call link (`tel:` link, phone-only), ⋯ menu, close.
- Status pill + source pill (leads) or discipline pill (students).
- Loss reason pill (if lead is "Отказ"): shows reason or "Указать причину" dashed button.
- Tabs (5): Инфо · Задачи · Комментарии · Семья · История статусов.
- Инфо tab: phone (staff-only) + call link, source/branch, tags, note.
- Задачи tab: 3 mock tasks with checkable TK-check buttons; "Новая задача" button (toast).
- Комментарии tab: 2 mock comments from staff; inline comment composer (send adds toast).
- Семья tab: 2 mock family members with open-card links; "Добавить члена семьи" button.
- История статусов tab: 4 status history rows with colored dot, name, date, author.
- "Перенести в «Ученики»" button (leads only) opens the cardMenu transfer flow.
- Teacher role: ⋯ menu shows only "Оставить комментарий" (K8 — read-only clients for teachers).
- Staff (manager/admin) ⋯: "Редактировать" (toast) + "Удалить" (toast + close drawer).
- Unsaved card state: `cardHead` always shows phone for staff, never for client/teacher POV.
- Staff card (teacher/staff kind from Users): shows role, discipline or access, student count, note.

### Расписание — Год view
- 12-month grid (3-col phone / 4-col desktop); each cell shows month name + lesson count (Aug 2026 = 6 lessons, others = 0).
- Year navigation: prev/next year buttons; "this year" label opens a toast.
- Click a month cell: sets `ST.schMonth`, switches to Месяц view.
- Filial selector (chip row): scopes schedule to one branch (rooms filtered by branch).
- Mode segmented control: Год / Месяц / День (shared across all three schedule sub-views).

### Расписание — Месяц view (K11)
- Default view on schedule open (K11 spec).
- Month header: clickable month-picker (pop-menu of 12 months).
- Skeleton shimmer for ~360ms before grid renders (K14).
- 7-col day-of-week grid; each cell: day number + lesson count badge for demo month days.
- Today cell highlighted with gold border.
- Days before month start shown as muted (non-interactive).
- Click a day: drills into Day view for that date (clamped to demo days 17–23 if in demo month).
- Month navigation: prev/next month shifts `ST.schMonth`/`ST.schYear` wrapping at year boundaries.

### Расписание — День view (day grid)
- Day strip (horizontal scroll): 7 days Mon–Sun with lesson-dot indicators; clicking jumps to that day.
- Branch selector (Филиал chip row): rescopes room columns.
- Segmented control: Комнаты / Преподаватели (switches column axis).
- Calendar grid: sticky time column (left, Z=7) + sticky room/teacher headers (top, Z=8) + sticky corner (Z=9); cells scroll under them (K10 fix).
- Hours 09:00–21:00 (13 rows × ROW_H=62px).
- Lessons placed absolutely in a `.lessons-layer` over the grid.
- Lesson sizing: `tiny` (<60min, 1 row), `compact` (60–90min, teacher hidden), `full` (≥90min).
- Partial fill: `--cut` CSS var on `.lesson.partial` for sub-hour remainder (hatch overlay).
- bookPop animation (`.justbooked`) on newly created lesson.
- Conflict detection: H6 — `findConflicts()` checks overlap for room or teacher before booking opens; shown inline in booking sheet.
- Teacher role: cells are `cursor:default`, no hover, `attachBlockSelect` returns early (K5).

### Расписание — Booking sheet
- Opens on pointer-up after vertical block-drag; or tap-on-cell = 1-block booking.
- Default duration = exact selected span in minutes (I8 fix: 2 blocks → 2:00).
- Duration stepper: +/−15 min buttons; quick-select chips (60/90/120/165/180).
- Sub-hour hint text: "Бронь займёт N блоков + rem/60 (X%) следующего".
- Full-hour hint: "Бронь займёт N блоков целиком".
- Student/group dropdown, Teacher dropdown, Room dropdown.
- Conflict warning rendered inside sheet if overlap found; button changes to red "Всё равно создать".
- Conflict rechecks on teacher/room dropdown change.
- Confirm: appends to LESSONS array, closes sheet, re-renders grid, shows toast with undo (removes lesson on undo).

### Расписание — Lesson sheet (view existing)
- Opens on click of any lesson block.
- Shows: discipline, time range + duration, student name, teacher name, room, status pill.
- Clarifying note: "Одно занятие на весь диапазон — не N отдельных часовых."
- Teacher role: comment composer shown instead of "Изменить" button (K5).
- Teacher comment send: clears field, shows toast.
- Manager/admin: "Изменить" button (toast stub).

### Пользователи (Users) — manager-only
- Full empty-state for non-manager roles.
- List of 6 mock users: avatar + online dot, name, kind chip (Ученик/Лид/Сотрудник/Преподаватель), contact, branch (desktop only), role chip (Управляющий/Администратор).
- Role chip: gold for Управляющий, blue for Администратор.
- Phone: role chip hidden on narrow phone (CSS K13 fix); role-edit shows icon only.
- "Роль" button (role-edit): opens pop-menu with Управляющий/Администратор options — mutates `USERS[i].role`, re-renders, toast.
- Role-edit disabled for non-manager (I9 fix): `disabled` attribute + tooltip "Только Управляющий"; click shows toast "Недоступно".
- Open-card icon (A2): clicks `openCardForKind(u.card)` — jumps to the related card type (lead/student/teacher/staff drawer).
- Row click (not on action buttons): also opens related card.
- Footer note explaining navigation.

### Отчёты (Reports) — manager-only, in-window tabs
- Segmented: Аналитика / Финансы.
- Skeleton shimmer on load (K14): 6 skel-cards for ~340ms then real content.

#### Аналитика tab (8 report cards)
- Воронка продаж: horizontal funnel bars (Лиды→Связались→Пробное→Купили).
- Сравнение филиалов: funnel bars per branch (branch.count×10).
- Причины потерь: muted funnel bars driven by `ST.lossReasons` live data + base counts (Дорого/Нет времени/Локация/Другое).
- Задолженности: big number (₽96 400) + 3 debtor list rows.
- Прогноз выручки: big number (₽910 000) + sparkline SVG (inline path, 8-point data).
- Отток (churn): 4.2% + delta.
- SLA чатов: 3м 12с + bar sparkline.
- Недельный отчёт: text summary (+38 лидов, 12 новых учеников, 96% посещаемость, 2 жалобы решены).
- Each card is clickable → toast with report name.

#### Финансы tab
- KPI cards: Доход за месяц (₽842k + bar sparkline), Расходы (sum of EXPENSES + bar sparkline), Чистая прибыль (₽524k), Должники (7, ₽96 400 + 3 debtor rows).
- Wide card: Расходы · детально — list of EXPENSES rows (title, category, date, amount in red); "Добавить расход" primary button.
- Add expense sheet: amount (numeric input), category (select from EXP_CATS), date (pre-filled today), comment; confirm validates amount > 0, optimistic-prepends to EXPENSES array, refreshes finance content, toast.
- Finance also accessible as standalone nav item (legacy stub re-routes to financeView); wired identically.

### Задачи (Tasks) — manager + admin (all roles see it but it's in admin nav too)
- List of 4 mock tasks (TASKS array): checkbox + title + subtitle.
- Checkbox toggle: mutates `task.done`, re-renders, toast "Задача выполнена" / "возвращена".
- Done tasks: strikethrough title + dimmed text.
- Row click: toast with task title.
- "Новая задача" button: appends `{t:'Новая задача', m:'Без срока', done:false}` to TASKS, re-renders, toast.

### Настройки (Settings) — manager-only
- Full empty-state for non-managers.
- Воронка лидов card: "Настроить воронку лидов" button opens column-editor drawer for ST.kColumns (global lead funnel); current column chips shown.
- Филиалы section (3 branches, each a set-card):
  - Branch header: name + address, edit button.
  - Воронка учеников sub-section: column chips, "Настроить воронку" opens column editor for that branch's cols.
  - Комнаты sub-section: list of rooms for that branch, edit buttons, "Добавить комнату".
- "Добавить филиал" button at bottom.
- Преподаватели card: list of all teachers with edit buttons; "Добавить преподавателя".
- Add/Edit sheet (openSetEdit): name input, address/specialization input, optional "Связать с аккаунтом / преподавателем" select. Delete button (existing items). Save mutates the live data array, re-renders, toast.

### Профиль (Profile) — staff roles (manager / admin / teacher)
- Hero section: avatar, name, role chip.
- Contact card: phone, branches, notification row.
- "Кабинет клиента — превью" section: privacy notice + kid-switch + subscription card + upcoming lessons + subscription renewal button. Rendered with `data-pov="client"` so phone numbers in this section are hidden.
- Легальные документы (K4): Политика конфиденциальности, Условия использования, Оферта — each opens an info sheet with demo text.
- "Запросить удаление аккаунта" (K4): opens confirmation sheet; confirm sends toast "Запрос отправлен".
- Profile pop-menu (rail avatar / appbar dots): "Мой профиль" → nav to profile, "Уведомления" → toast, "Выйти" → logout.

### Профиль (Profile) — Клиент role
- Different view: avatar, name "Анна Смирнова", "Клиент · MagicMusic" chip.
- Contact card: masked phone (+7 999 ••• •• 67), email, branch.
- Settings list: Уведомления, Язык приложения, Тёмная тема, Помощь и поддержка — each row → toast; "Выйти" row → logout.
- Легальные документы + удаление аккаунта (same as staff profile).

### Моя школа (My School) — Клиент role
- Kid switcher: chip row with Миша (active), Соня, + Добавить. Switching chips updates name/subtitle in the subscription card.
- Subscription card: gradient gold card, plan name "Абонемент · Вокал", active status pill, kid name, remaining lessons text "6 из 8 · до 31 авг", progress bar at 75%.
- Upcoming lessons: 2 list rows (date, time, teacher, room) — static mock.
- Домашнее задание: 2 tasks with checkable TK-check; checking toggles `.done` class + icon + toast.
- "Продлить абонемент" primary button → toast.
- Entire view uses `data-pov="client"` so no phone numbers or call links visible.

### Ученики (My Students) — Преподаватель role
- Search bar filters MY_STUDENTS (3 mock students: name + discipline + tags).
- List rows: avatar, name, discipline chip, tag chips, open-card icon.
- No phone numbers or call links (data-pov="teacher").
- Open-card icon → student card drawer.
- Privacy hint bar: "Преподаватель видит только своих учеников."

### Skeleton loaders (K14)
- Chat list: 6 avatar + 2 text-line rows shimmer for 320ms.
- Kanban: 4 columns × 3 cards shimmer for 340ms.
- Schedule day grid: full-height skel-card for 360ms.
- Schedule month: dow row + 35 cell skeletons for 360ms.
- Reports/Finance: 6 skel-cards for 340ms.

### Optimistic UI patterns (K6/K14)
- Card send: bubble appears in conversation immediately.
- Kanban card transfer: card removed from leads, appears in students with `.pending` class + "Переносится…" tag; settles after 900ms.
- Expense add: prepended to EXPENSES list immediately.
- All with "Отменить" toast on transfers (rolls back mutation and re-renders).

### Toast system
- Bottom-center positioned (above tab bar); stacked for multiple.
- Auto-dismiss 4200ms with fade-out.
- Optional "Отменить" undo button that calls a callback then dismisses.
- Success icon (green check badge).

### Pop-menu system
- Absolute-positioned, animates in (scale + translateY).
- Auto-positions relative to anchor button (flips up if near bottom).
- Supports: section labels, separators, items with icon + label, danger variant.
- Closes on outside click (pointerdown once-listener) or Escape key.
- Used for: role switch, chat menu, card ⋯ menu, transfer branch/disc picker, loss reason picker, nav overflow ("Ещё"), month picker, profile menu.

### Drawer overlays
- filters: slide in from right; chip/select filters; close, reset, apply.
- cols: column editor; rename + reorder + delete + add.
- card: client/staff card; full-height drawer.

### Sheet overlays
- book: booking sheet (schedule → new lesson).
- lesson: existing lesson detail.
- convert: overlay tag (exists in HTML but content rendered by transfer flow).
- info: reused for add-expense, add/edit settings items, legal docs, account deletion.

### Keyboard / accessibility
- Escape key closes all open drawers and sheets and the pop-menu.
- `aria-label` on icon buttons throughout.
- `:focus-visible` outline using gold color.
- `prefers-reduced-motion`: all transitions set to 0.01ms, shimmer animation disabled.
- `touch-action: pan-y` on draggable cards; pointer events used (not touch events) for cross-device support.

### Call link behavior (H1/H2/I1)
- `<a class="call-link" href="tel:+79162240871">` — real tel: link opening device dialer.
- Visible only in: phone frame chat conversation header + open card phone row.
- Hidden via CSS: on desktop (`html[data-frame="desktop"] a.call-link { display:none }`), on kanban cards (`.card a.call-link { display:none }`), for client/teacher POV (`[data-pov] .call-link { display:none }`).

### Scrollbar hiding (I2/H4)
- `*{ scrollbar-width:none; -ms-overflow-style:none }` + `::-webkit-scrollbar { display:none }` applied globally.

---

## 3. Per-role behavior / permissions

### Управляющий (Manager)
- Full nav: Чат · Расписание · Клиенты · Задачи · Отчёты (primary 4 + Ещё overflow on phone) · Пользователи · Настройки.
- Can create/drag/transfer leads; can book schedule; can edit columns; can change user roles; can add expenses; sees all phone numbers and call links.
- Profile: staff hero + client portal preview + legal + delete.

### Администратор (Admin)
- Nav: Чат · Расписание · Клиенты · Задачи.
- `[data-mgr]` elements hidden (Пользователи nav item, role-change controls).
- Role-edit button disabled with tooltip "Только Управляющий".
- Can create leads, book schedule, see client phones.
- No Reports, Finance, Users, Settings.

### Преподаватель (Teacher)
- Nav: Чат · Расписание · Ученики.
- Schedule: cells non-interactive (no booking, no drag-select).
- Client card ⋯ menu: "Оставить комментарий" only.
- Lesson sheet: shows comment composer instead of "Изменить".
- My Students view: own 3 students, no phone numbers, no call links.
- `data-pov="teacher"` on mystudents view and lesson comment.

### Клиент (Client)
- Nav: Чат · Моя школа · Профиль.
- Чат: can send messages; no call link in conversation header (data-pov="client" on myschool, clientProfileView uses it too).
- Моя школа: kid switcher, subscription card, upcoming lessons, homework.
- Профиль: own profile with masked phone, settings, legal, logout.
- Cannot see kanban, schedule booking, reports, users, tasks, settings.
- `data-pov="client"` suppresses all `.staff-phone` and `.call-link`.

---

## 4. Data / schema touched (in-memory mock arrays)

| Entity | Fields | Count |
|---|---|---|
| LEAD_STATUSES | id, name, color | 6 |
| DISCIPLINES | id, name, color | 4 (mutable) |
| BRANCHES | id, name, addr, count, cols[] | 3 (mutable) |
| LEADS | id, name, phone, status, src, tags[], note, saved, pending? | 11 (mutable) |
| STUDENTS | id, name, phone, branch, disc, tags[], note, pending? | 8 (mutable) |
| ROOMS | id, name, sub (discipline), branch | 7 (mutable) |
| TEACHERS | id, name, sub (discipline), link? | 6 (mutable) |
| LESSONS | id, startH, durMin, room, teacher, student, disc | 7 (mutable) |
| USERS | name, role, kind, online, card, contact, branch | 6 (mutable role field) |
| CHATS | id, name, kind, online, time, unread, prev, muted, me, read | 6 |
| MSGS | keyed by chat id; arrays of {sep?/in/t/voice/dur/time/read} | ~12 messages |
| TASKS | id, t (title), m (meta), done | 4 (mutable) |
| EXPENSES | id, title, cat, date, amount | 4 (mutable) |
| EXP_CATS | string[] | 6 |
| LOSS_REASONS | string[] | 4 |
| MY_STUDENTS | name, disc, tags[], note | 3 |
| ST (state) | frame, role, navPhone, navDesk, clientTab, schView, activeDay, schMode, schMonth, schYear, schBranch, stuBranch, chatOpen, chatPane, kColumns[], sColumns[], repTab, lossReasons{}, kid, authed, authMode | single object |

Schema notes:
- `BRANCHES[i].cols` is a deep-copy of DISCIPLINES + misc; each branch has independent funnel columns.
- Phone numbers are raw strings in mock data; `norm()` strips non-digit for tel: links and search matching.
- `LEADS[i].saved` flag exists in mock data but is never checked in the prototype JS (all leads shown as already-saved; "Сохранить в CRM" removed per I3 fix).
- `LESSONS` are shared across all views (no branch scoping for the demo month); in practice rooms are branch-scoped.

---

## 5. Notable business rules / edge cases

- **Tap vs drag threshold (E1 fix):** `THRESH=6` pixels of pointer movement required before drag mode activates; under threshold, pointerup is treated as a click to open the card.
- **Dwell-before-transfer (H7):** 350ms dwell + ≤10px jitter tolerance required to trigger tab expansion or branch/discipline reveal. Quick pass-through does NOT trigger. Visual progress ring fills during dwell.
- **Optimistic transfer + undo window:** Card is moved immediately to STUDENTS; a 4.2-second toast undo window allows reverting. After undo, card re-appears in LEADS at the same position.
- **Conflict detection is pre-save only:** `findConflicts()` runs when the booking sheet is open and on room/teacher change. Conflicts display a warning but do NOT block creation — "Всё равно создать" overrides.
- **Partial block fill is display-only:** `--cut` CSS var on `.lesson.partial` draws a hatch overlay on the fractional last block. It does not prevent overlapping bookings.
- **Duration default = exact span:** 2-block drag = 2:00 default (not 1:45). Sub-hour fractions only appear when user manually adjusts the stepper or quick-select.
- **Dropping into "Отказ" column auto-prompts loss reason** (delayed 120ms setTimeout to let the kanban re-render first).
- **Loss reasons feed Reports live:** `ST.lossReasons` selections are reflected in the "Причины потерь" funnel immediately (base counts + 3 per selection).
- **Student board is per-branch:** switching `ST.stuBranch` changes which students are shown AND which funnel columns are used (each branch has independent cols). The kanban columns in the students board come from `branchById(ST.stuBranch).cols`, not the global DISCIPLINES array.
- **Lead funnel is global (cross-branch):** LEAD_STATUSES is one global array; all leads regardless of branch use the same funnel columns.
- **Column editor is dual-target:** `CC_TARGET` ('lead'|'student') and `CC_BRANCH` determine which columns array is mutated. Lead funnel edits affect `ST.kColumns`; student funnel edits affect `BRANCHES[i].cols`.
- **No unsaved-contact special state:** All mock data has `saved:true`. The "Сохранить в CRM" menu item was removed (I3 fix); it is absent from all ⋯ menus in the prototype.
- **Teacher lesson comment (K5):** teacher clicking a lesson block gets the lesson detail sheet with a comment text field but no edit button. Submit clears field and shows toast (no persistent storage).
- **Schedule mode memory:** `ST.schMode` persists across nav changes; returning to schedule remembers Год/Месяц/День state.
- **Auth is demo-only:** Any non-empty email+password pair passes login. "Войти как…" quick buttons bypass credential check entirely. `ST.authed` is only in-memory; refreshing the page resets to logged-out.
- **Phone number masking for clients:** Client profile shows `+7 999 ••• •• 67` — hardcoded masked string, not derived from real data. Actual number hidden via CSS `data-pov="client"` on staff-phone elements.
- **Desktop call link fully suppressed:** `html[data-frame="desktop"] a.call-link { display:none !important }` — no call affordance anywhere on desktop regardless of role.
- **Rail avatar initials are role-hardcoded:** `railAvaInit()` returns fixed 2-letter codes per role (АП=manager, ИС=admin/teacher, АС=client) rather than derived from user data.
- **Skeleton and real content race:** Skeleton is set synchronously, real content replaces it in setTimeout (320–360ms). If the user navigates away during the delay, the `$('#kanbanWrap', activeApp())` lookup will find a different element or null; the `if(w)` guard prevents a crash but the transition is fire-and-forget.
- **Escape key closes all overlays globally** (document-level listener), including across frame switches.
- **Resize handler** re-renders the grid and re-measures segmented control glides; does not re-render the whole app (only schedule grid + glides + toggles).
