# MagicMusicCRM — owner feedback after on-device test + CRM redesign brief (2026-06-20)

Owner tested the built APK + Windows release. Verdict: only part of the work surfaced correctly; many real bugs, an RBAC violation, dirty import data, and the Schedule window is conceptually broken. Owner wants **browser-testable mockups of all CRM windows FIRST** (design-first, click-through approval), then implementation. Design bar: production-grade, anti-"нейрослоп", Telegram-grade craft. Brand locked: gold `#C5A059`, charcoal `#101012`, dark Telegram aesthetic.

---

## A. RBAC / Иерархия (CRITICAL — access control)
- **A1.** Hierarchy is **Manager (Управляющий) > Admin (Администратор)** always. Admin must access **only Чат, Расписание, Клиенты** — NOT Пользователи. Admin must NOT change roles (own or others'). Currently both admins AND managers reach Пользователи + can mutate roles → breaks hierarchy.
- **A2.** From Пользователи, the Manager must be able to **jump to the related card** of a user: Ученик / Лид / Преподаватель / Сотрудник. Currently no navigation.
- **A3.** **Delete codex smoke users** from the system.

## B. Import data quality
- **B1.** Comments/notes are NOT on all leads though they existed in HolliHop. Import incomplete (export-import matched by phone only; many missed).
- **B2.** Most leads got email imported as `holli-hop-error@example.com` — nonsense. Prefer **empty** over a fake error email. Clean these.
- **B3.** Phone **not normalized everywhere** — old cards still hold the old un-normalized format. Need a one-time normalize pass + every read path normalized.
- **B4.** (see D2) schedule import splits one long lesson into N hourly lessons.

## C. Окно «Клиенты»
- **C1.** No card transfer between Лиды ↔ Ученики — there is no cross-window card move.
- **C2.** «Ученики» is just a button; while a card is **held (dragging)** it should morph into a **drop "folder"** target to transfer the client card into Students.
- **C3.** Filters are still **one row**. Need a **slide-out filter menu** + a **persistent search bar**.
- **C4.** Ученики tab **won't open** — "Не удалось загрузить учеников" (load bug: studentBoardProvider / branch-disciplines fetch fails).
- **C5.** Adding/configuring **column names & order doesn't work** (C8 reorder broken on-device).

## D. Расписание (major redesign)
- **D1.** Branch shows e.g. "48 lessons" in a day, but inside the day it says **no lessons** and shows the dumb "На этот день нет занятий, добавить новое?" instead of a calendar grid.
- **D2.** Import logic violation: a long lesson (e.g. 3h) is counted as **N separate hourly lessons** ("3 занятия" instead of 1). Same in teacher filter.
- **D3.** **NEW Schedule UX (owner concept):** the calendar is a grid of hidden blocks. The user **press-drags a VERTICAL range of blocks** (never horizontal — horizontal would break the room/time logic) to select a span (e.g. 13:00–16:00). On release, a **booking sheet opens immediately** → pick student / teacher / room / exact duration. If they pick 2h45m, the booking fills **2 full blocks + a 45/60 coefficient (percentage) of the 3rd block**. One lesson covers the whole span.
- **D4.** Same model for the **teacher filter** (room-view AND teacher-view columns).
- **D5.** **Tap a single square** = add a 1-hour lesson there.
- **D6.** Highest UX/UI + animations for all of this.
- **D7.** Bug: a lesson shows the **teacher name**, but opening its card says "Ученик: Не назначен" — wrong.
- **D8.** **Double month header**: top correctly "Август 2026", just below incorrectly "августа 2026".

## E. Cross-cutting bugs
- **E1.** **False tap→drag**: on PC, a single click to OPEN a card immediately starts drag mode. Need a drag threshold / distinguish tap vs drag.
- **E2.** Voice message records but **won't play** — "Ошибка воспроизведения source error (0)".
- **E3.** Image/video send window bugs; the attachment "flies away"; it opens the **Google account media** instead of the **device gallery** (must be like Telegram — device gallery/camera).
- **E4.** **Splash**: first a white screen with a badly-cropped app emblem, THEN the proper branded loading screen with uncropped emblem + indicator. Fix the first frame.
- **E5.** **PC**: opening a NEW (unsaved) contact card does NOT show "Этот контакт ещё не сохранён в CRM" (phone shows it correctly).
- **E6.** **Обзор системы** window is meaningless — mostly leads to Пользователи → propose removing it.

## F. Process
- **F1.** FIRST: browser-testable mockups of all CRM windows, interactive, for owner to click through and approve. THEN implement in Flutter.

---

## Design direction (locked)
- Brand: gold `#C5A059` (accent/primary), secondary `#BFA37E`. Dark: bg `#101012`, surface `#1A1A1D`, sidebar `#151518`, input `#242427`, divider `#2A2A2D`. Text `#FFFFFF` / secondary `#A1A1AA`. Online `#10B981`, danger red.
- Telegram-grade craft. Anti-slop: no gradient text, no glassmorphism-as-default, no side-stripe borders, no identical card grids, no tiny tracked eyebrows. SVG icons only. Motion 150–300ms ease-out, drag tracks the finger in real time, reduced-motion fallback.
- Touch ≥44px, contrast ≥4.5:1, focus states, deep-linkable windows.

## Mockup plan (browser, self-contained, brand-matched)
1. **Nav shell** — RBAC-correct (Manager full nav incl. Пользователи; Admin only Чат/Расписание/Клиенты, no role edit). Role toggle to demo both.
2. **Клиенты** — Лиды/Ученики kanbans; press-drag a card → «Ученики» segment morphs into a drop-folder; slide-out filters + persistent search; column add/rename/reorder.
3. **Расписание** — the block-booking calendar (vertical block drag-select → booking sheet with sub-hour coefficient; room-view + teacher-view; tap=1h; the "48→real grid" fix; correct single month header).
4. **Карточка клиента** — unified (lead+student), Семья + История статусов, cross-window transfer entry, "not saved in CRM" state.
5. **Пользователи** — Manager-only, jump-to-related-card, no role mutation by admin.

---

## v2 feedback (after prototype v1)
- **G1. App-accurate, not web PWA.** v1 reads as a web admin dashboard. Redesign must look like OUR actual Flutter app — messenger-first, Telegram-style dark, gold brand — shown in BOTH a phone frame (mobile layout, bottom nav, full-screen windows) AND a desktop app window (adaptive 2-pane messenger shell / rail). Only then can the owner judge it.
- **G2. Show ALL functionality**, including **Чат** (Telegram-style: chat list + conversation, gold outgoing bubbles, message input, emoji/attach), Расписание, Клиенты, Пользователи, client/lesson cards, profile, client portal. Every major window present.
- **G3. In-kanban drag-and-drop** in Клиенты: cards reorder within a column AND move between status columns (Лиды funnel) by D&D — with lift + insertion indicator. (Currently impossible.)
- **G4. Continuous lead→student transfer (not a modal).** Holding a lead card and bringing it to «Ученики» should carry **that same card "in hand" INTO the Ученики section**. There the user drops it: first into the correct **Филиал**, then into the correct discipline/funnel **column**, OR into a **«Разноплановые»** (uncategorized) column. The drag is one continuous gesture across windows.
- **G5. Drop zones grow + dashed outline while dragging** — when a card is held, valid drop areas enlarge and get a dashed contour for precise targeting.
- **G6. Branch drop-zones first in Ученики.** On entering Ученики mid-drag, show **Филиал drop-zones** first (big, dashed) → drop into a branch → then its columns appear → drop into a column.
- **G7. Keep the ⋯ explicit-action menu** as the non-drag alternative ("Перенести в Ученики → выбрать филиал + колонку").

---

## v3 feedback (after prototype v2) — liked: card design + concept, call icon
- **H1. Call icon → device dialer.** Tapping the call icon opens the phone app's dialer on the user's own device with the client's number pre-filled (`tel:` link). It does NOT call inside the app.
- **H2. Phone/call RBAC.** Only **Manager + Admin** (staff) see client phone numbers and call buttons. **Clients (non-staff) and Teachers must NOT** see other clients' phone numbers or have call access. Hide numbers + call affordance in client/teacher contexts.
- **H3. Fix text overflow** everywhere — text escapes its "screen" bounds on BOTH phone and desktop. Truncate/wrap so nothing overflows.
- **H4. Scrollbars look убого.** Replace the default horizontal+vertical scrollbars with thin, styled, on-brand (or overlay/auto-hiding) scrollbars across the app.
- **H5. Schedule sticky headers.** When scrolling the calendar, the **time-slot column** (left) and the **room/teacher column headers** (top) must stay pinned/visible. Don't lose context on scroll.
- **H6. Schedule conflict warning.** Creating a lesson at a time already occupied for that room/teacher → show a conflict warning (pre-save check).
- **H7. NEW drag model (owner's vision — replaces the drop-folder).** While **holding** a client card and moving it toward the «Лиды | Ученики» segmented control, **those tabs expand IN PLACE into drop zones** (right where the labels are, enlarged + dashed). When the held card stays inside the «Ученики» zone for a couple of frames — **debounced, no false triggers** — the view **switches immediately to the Ученики board** (card still in hand) with a prompt to pick a **Филиал**; same dwell-debounce logic → then transfer into the chosen branch's kanban column (or «Разноплановые»). Keep the ⋯ explicit-action menu too. The earlier "morph button into folder" approach is rejected in favor of this in-place tab-expansion + dwell-switch.

---

## v4 feedback (after v3) — owner frustrated: still incomplete + non-functional + slop
- **I1. Call icon — wrong placement.** NO call icon on DESKTOP at all. NO call icon on client cards in the Клиенты kanban. Call icon ONLY in: (a) chats, (b) next to the phone number inside the open client card / profile. Restore the v2 call-icon visual (looked better than v3).
- **I2. Scrollbars are unacceptable** for an app (PC + phone). HIDE them — no visible scrollbars anywhere; content scrolls but the bar is invisible/overlay/auto-hide (app-native, not web).
- **I3. ⋯ menu "Сохранить в CRM" on already-saved cards is dumb** — only show "Сохранить в CRM" for UNSAVED contacts; saved client/lead cards must not offer it.
- **I4. EVERY button must work** in the simulator — filters buttons, chat buttons (PC+phone), all menus. Currently many do nothing. Wire real prototype behavior to all.
- **I5. Simulate ALL 4 roles separately:** Клиент, Преподаватель, Администратор, Управляющий — each with its OWN nav + permitted windows + data visibility, so the owner can experience each role. (Not just Управляющий/Администратор.)
- **I6. Missing Отчёты/Аналитика (Reports/Statistics) for Управляющий** — the app has a reports+stats section (management dashboard, 8 reports). Add it.
- **I7. Text still overflows**, including dropdown menu items after a button opens a list — fix ALL overflow incl. menus/popovers.
- **I8. Booking default duration = the exact selected span.** Drag-select 2 hours → default shows **2:00**, not 1:45. The PARTIAL fill is only when the USER manually types a sub-hour duration (e.g. 1:45) — then the block visually fills NOT to the end of the last hour (45/60 of it). Fix the default + the partial-render semantics.
- **I9. Role-change UI (Управляющий editing a user's role) is not rendered** — show it (a role dropdown/action in Пользователи, available ONLY to Управляющий).
- **I10. Пользователи section: field text overlaps** — fix the layout so fields don't collide.
- **I11. Overall: deliver the COMPLETE improved visual of the app's existing feature set per role, fully clickable.** Ground every window in the real app's functionality.

---

## Real-app role navigation (ground truth for the v4 prototype)
Four roles, each renders a different app (its own nav + permitted windows + data visibility). The prototype must simulate all four via a «Роль» switch (Клиент · Преподаватель · Администратор · Управляющий) plus 📱/🖥 frame switch.
- **Управляющий (manager):** Чат · Расписание · Клиенты · **Финансы** · **Задачи** · **Отчёты** · Пользователи. (No «Обзор».) Full access; edits user roles.
- **Администратор (admin):** ONLY Чат · Расписание · Клиенты. No Пользователи/Финансы/Задачи/Отчёты; cannot edit roles.
- **Преподаватель (teacher):** Чат · Расписание · Ученики (own students only). Never sees other clients' phone numbers / call buttons.
- **Клиент (client):** Чат · Моя школа (абонемент · расписание занятий · домашка) · Профиль. Never sees other clients' numbers / calls.
**Отчёты** content (manager): funnel · branch comparison · loss reasons · debts · revenue forecast · churn · chat SLA · weekly — on-brand cards + simple inline-SVG bars/lines. **Финансы:** revenue/expense/debtors. **Задачи:** task list. All mock data, all clickable.

---

## v5 direction (after v4) — owner: v3 was visually MUCH better; do NOT redesign
- **J1. v3 is the locked visual base.** v4 regressed (stripped richness, looked dumb/inconvenient). DISCARD v4's look. Build v5 by COPYING v3 and editing it SURGICALLY. Do not restyle existing v3 screens, do not rebuild, do not change v3's layout/spacing/cards/visual language.
- **J2. Only two kinds of change allowed:** (a) the small targeted fixes below; (b) ADD the per-role perspective + role-specific windows, built with v3's OWN existing CSS classes/components so they look native to v3.
- **J3. Surgical fixes to apply on the v3 base:**
  - Hide all scrollbars (I2).
  - Remove the call icon from DESKTOP entirely AND from the Клиенты kanban cards. Call icon stays ONLY in the phone chat header + the phone open-card phone line. No call on PC at all. (I1 final.)
  - "Сохранить в CRM" in ⋯ only for UNSAVED contacts (I3).
  - Fix any text overflow incl. open dropdowns/popovers (I7).
  - Booking default duration = the exact selected span (2 blocks → 2:00); partial block-fill only when the user types a sub-hour (I8).
  - Пользователи: no overlapping field text (I10).
  - Role-change works for Управляющий, disabled for Администратор (I9).
- **J4. Add the 4-role perspective** (Клиент · Преподаватель · Администратор · Управляющий) per the "Real-app role navigation" section: per-role nav + Управляющий's Отчёты/Финансы/Задачи + Клиент portal + Преподаватель students — all rendered in v3's existing visual style (reuse v3 components), NOT a new look.

---

## v6 feedback (after v5) — REFINE v5, do NOT build new (copy v5 → v6, surgical)
- **K1.** Wire ALL remaining dead buttons — every control does something.
- **K2. Login/auth (redesigned):** a redesigned login screen before the app; ability to **Войти / Зарегистрироваться (создать аккаунт) / Выйти**. Logout (from profile) returns to the login screen; login enters the app.
- **K3.** Remove duplicated buttons / duplicated functionality.
- **K4. Profile additions:** «Легальные документы» (links: Политика конфиденциальности, Условия использования, Оферта) + «Запросить удаление аккаунта».
- **K5. Teacher cannot create/assign lessons** — no «Новое занятие»/block-booking for teacher. Teacher may ONLY leave comments on lessons.
- **K6. Optimistic transfer:** Лиды→Ученики card move is INSTANT (optimistic UI). Remove the long response/lag.
- **K7.** Widen the Chats search bar (currently too narrow).
- **K8. Teacher cannot edit Лиды/Ученики** (no editing, no ⋯ transfer/role) — clients are read-only to a teacher; teacher only leaves lesson comments.
- **K9. Client cannot add other students** to lessons/groups.
- **K10. Schedule sticky fix:** time column (left) + room/teacher header row (top) stay PINNED; the grid scrolls UNDER them smoothly (cells hide behind the sticky headers), NOT floating/overlapping/sliding across. Correct position:sticky + opaque header backgrounds + z-index so the canvas slides beneath.
- **K11. Month view first:** the schedule opens on a MONTH calendar (grid of the month's days with a quick per-day lesson overview) → tap a day → drill into the current day-grid; keep the nearby-days strip inside the day view + the day-drill that exists now.
- **K12. Manager nav order:** Задачи is primary (in the 4 tabs), Финансы moves to «Ещё». Tabs: Чат·Расписание·Клиенты·Задачи + Ещё{Финансы·Отчёты·Пользователи}.
- **K13. Пользователи rows** still overlap/cramped/unreadable — fix to clean readable columns. App-wide alignment + truncation audit: no cut-off/unreadable text, no misaligned elements.
- **K14. Optimistic UI + Skeletons:** skeleton loaders on view loads (chat list, clients, schedule, reports) + optimistic updates (card move, send, role change) for a fast, organic feel.
- Constraint: keep v5's visual; only refine + add the above in v5's style.
