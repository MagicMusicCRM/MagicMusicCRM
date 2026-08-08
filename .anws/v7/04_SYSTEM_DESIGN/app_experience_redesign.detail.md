# App Experience Redesign — Detailed UX Contract

> Companion to `app_experience_redesign.md`. This document is implementation-level product behavior, not a replacement for backend/domain specifications.

## 1. Screen and role matrix

Legend: `P` primary navigation, `S` secondary/contextual, `R` read-only or reduced action set, `—` absent and not prefetched.

| Surface | Client | Teacher | Admin | Manager | Director |
|---|:---:|:---:|:---:|:---:|:---:|
| Chat | P | P | P | P | P |
| Own/assigned schedule | P | P/R | — | — | — |
| Operational schedule | — | R | P | P | P |
| Clients | Own profile | Assigned/R | P | P | P |
| Tasks | Own relevant | Assigned | Contextual | P | P |
| Operational dashboard | — | — | — | P | P |
| School finance/financial analytics | — | — | — | — | P |
| Users and roles | — | — | — | Capability-limited | P |
| CRM configuration | — | — | — | Delegated only | P |
| Personal settings | P | P | P | P | P |

Rules:

1. Capability projection can remove a listed surface; it cannot add data outside server scope.
2. Admin is intentionally below Manager and is limited to Chat/Schedule/Clients
   plus branch-scoped task read/close; task create/edit remains Manager+.
3. Manager must not request school-finance endpoints when sections are absent.
4. Teacher quick links cannot reveal contacts, representatives, finance, subscriptions, cost/debt or private comments.

## 2. Navigation metadata contract

Each production route must supply or derive the following metadata through existing router/entity infrastructure:

| Field | Required | Notes |
|---|:---:|---|
| `routeName` | Yes | Stable identity, not localized title |
| typed params | Yes | UUID/type/scope; no display-name lookup |
| `parent` | Nested routes | Lazy actor-safe parent location |
| `title` | Yes | Actor-safe; tombstone title if archived/deleted |
| `requiredAccess` | Yes | Capability + resource scope declaration |
| `surfaceKind` | Yes | `primary`, `quickView`, `selection`, `confirmation`, `comparison` |
| `viewStateVersion` | Restorable | Invalid version falls back safely |
| `serializeViewState` | Restorable | Filters/date/mode/position, no domain record cache |
| `defaultScope` | Scope-aware | Client branch, last permitted scope or route default |

### 2.1 Breadcrumb examples

| Current route | Expanded trail | Compact title/path menu |
|---|---|---|
| Student payments | Clients → Sokol → Anna Smirnova → Payments | `Payments` / path menu |
| Lesson details | Schedule → 04 Aug 2026 → 14:00 · Anna | `Lesson · 14:00` |
| Config field | Settings → CRM configuration → Students → Contact → Instrument | `Instrument field` |
| Report drilldown | Analytics → Aug 2026 → Sokol → Debtors | `Debtors` |

Current node is text, not a link. Ancestors are focusable buttons. When width is insufficient, oldest middle nodes collapse into `…`; the root and nearest parent remain when possible. Menu order preserves hierarchy.

### 2.2 Entity link behavior

| Input | Current-tab action | Explicit alternate action | Failure state |
|---|---|---|---|
| ClientRef | Open client workspace | Open in new desktop tab | Actor-safe unavailable card |
| TeacherRef | Open allowed teacher context | New tab | No contact/private data prefetch |
| RoomRef | Open room/schedule context | New tab | Neutral missing/forbidden state |
| LessonRef | Open quick view or full route by intent | New tab on desktop | Preserve source calendar state |
| Task/Payment/SubscriptionRef | Open canonical domain route | New tab | No legacy duplicate screen |

Clickable rows show hover/focus and directional affordance. Plain text without an authorized typed ref stays plain text.

## 3. Workspace tab contract

### 3.1 Visual anatomy

Tab contains: entity/section icon, concise title, optional dirty dot, optional close button. Active state uses surface contrast and gold focus/selection accent, not a heavy filled gold tab. Hover reveals close; keyboard focus remains visible.

### 3.2 Behavior

- Maximum 10 tabs; opening the eleventh prompts to close/select an existing tab rather than silently evicting work.
- Drag to reorder; keyboard alternative via context menu `Move left/right`.
- `Duplicate` copies safe location/view state, not mutable form state.
- `Close others` and logout pass through dirty-form decision.
- Per-account store key includes account identity and schema version.
- Startup restores only access-valid routes. Invalid entries are omitted with one non-blocking summary notice.
- Logout clears the current account tab cache immediately; user B never observes user A's tabs.

### 3.3 Desktop history

History belongs to each tab. Back/Forward buttons show disabled state and tooltip; long press/context menu may show a short actor-safe history list only if supported without storing secrets. This list is optional and not required for v6.

## 4. Adaptive surface specifications

### 4.1 Full-screen route

- Compact: edge-to-edge Scaffold, SafeArea-aware app bar, 16px content gutters, one-column reading order.
- Expanded: content constrained only where readability requires it; dense tables/calendars use full work width.
- Sticky footer only for important form actions; it must not cover validation or final field.
- Loading uses stable skeleton geometry; route title is available immediately from safe metadata.

### 4.2 Draggable mobile sheet

| Property | Contract |
|---|---|
| Width | 100% of safe width on compact; no floating 16–24px outer margin |
| Corners | Top corners only at partial extent; visually flatten at full-screen state |
| Initial size | ~0.58, adjusted down only for truly short content |
| Snap sizes | 0.58 / 0.90 / 1.00 for content sheets; fewer for short selection |
| Handle | Visible, semantic, 36–48px target area |
| Expand | Explicit labelled action in header; drag remains available |
| Scroll | Primary list/form consumes controller provided by `DraggableScrollableSheet` |
| Back | First dismiss nested menu/dialog, then sheet through dirty-state contract |
| Keyboard | Animated inset; focused field and primary action remain visible |
| Desktop | Mouse drag handle opt-in only where a draggable sheet is intentionally used |

### 4.3 Dialog

Dialogs are limited to one decision or short input. Maximum one primary and one secondary action, plus optional destructive action when the dialog explains impact. Long forms, client cards, payment forms and report views are forbidden in dialogs.

## 5. Desktop scrolling and input

### 5.1 Scroll surface ownership

| Surface | Vertical owner | Horizontal owner | Notes |
|---|---|---|---|
| Standard page/form | Page body | None | One visible vertical desktop bar on overflow |
| Data table | Page or table region | Table region | Horizontal bar remains reachable without scrolling to far bottom where practical |
| Student kanban | Board viewport | Board viewport | Wheel vertical; Shift+wheel horizontal; column inner lists own vertical scroll only if height bounded |
| Calendar | Calendar viewport | Timeline/grid | Sticky headers/time column; no controller sharing |
| Workspace tabs | None | Tab strip | Overflow arrows/menu plus draggable horizontal thumb if scrolling |
| Client section | Section body/page | Table/calendar child | Explicit nesting and pointer policy |

Global theme controls color, thickness, radius and hover expansion. Widgets own controllers and bars. A debug/test assertion must catch one controller attached to multiple scroll positions.

### 5.2 Keyboard and mouse baseline

- Tab/Shift+Tab: logical focus traversal.
- Enter/Space: activate focused control.
- Escape: dismiss top dismissible overlay; never discard dirty input.
- Alt+Left/Right: Back/Forward in active desktop tab where the platform permits.
- Ctrl/Cmd+W: close active workspace tab through dirty policy; not required on mobile.
- Context menu or visible overflow provides all actions that are otherwise pointer gestures.
- Pointer hover never reveals the only path to an action.

## 6. Per-role workflow targets

### 6.1 Client

Landing emphasizes next lesson, unread messages and immediate action. Navigation labels are plain language: `Главная`, `Расписание`, `Чат`, `Профиль`. Financial/status terminology is shown only for the client's own permitted information. Empty states explain whom to contact rather than exposing administrative tools.

Top workflow: notification/deep link → lesson/homework/message → related allowed context → system Back returns to source.

### 6.2 Teacher

Landing emphasizes Today/Week and next lesson. Schedule is read-only Day/Week. Lesson card offers allowed client identity, homework/history and shared comment context without edit/create/drag/attendance actions. Touch-first controls remain comfortable; desktop gains keyboard/mouse parity.

Top workflow: Today → lesson → assigned client context → homework/history → Back to exact time position.

### 6.3 Admin

Landing emphasizes today's schedule, search and client work. Only Chat, Schedule and Clients appear as primary destinations. Client create/edit and lesson operations follow capabilities. No Users/Config/managerial analytics entry points appear or preload.

Top workflow: Schedule/client search → client full workspace → lesson/payment allowed actions → return without losing filter/date.

### 6.4 Manager

Landing emphasizes operational workload: client funnels, tasks, schedule conflicts and permitted operational reports. Client-card payments remain available when `canReadStudentFinance`; school finance cards/routes/requests remain absent.

Top workflow: operational alert → filtered board/list → client/task/lesson → related user/branch → Back to the same filtered result.

### 6.5 Director

Landing emphasizes school/branch comparison, finance, data quality and configuration changes. Scope selector is prominent. Configuration and access changes use draft/preview/confirm/audit patterns. Delegation offers roles/capabilities strictly below the actor.

Top workflow: school dashboard → branch drilldown → record → correction/config preview → publish → audit evidence → return to dashboard filters.

## 7. Core domain layouts

### 7.1 Client workspace

Desktop uses the full work area with a compact identity header, key status/actions and one vertical page scrollbar. There is no desktop section tab bar: all capability-projected sections render in a stable reading order, large widths place compatible cards in two-column rows, and form controls keep a readable bounded width. A section deep link scrolls/focuses the corresponding heading. Mobile uses a concise identity app bar and scrollable section tabs/menu for the remaining destinations. Canonical sections:

1. `Обзор` — essential identity, branch, responsible staff, lifecycle, next action, canonical required Advertising source, primary Request type/Learning goal/Level/Category/Lesson type, and a collapsed configuration-driven `Дополнительные поля` region on desktop and mobile. Legacy `adSource`/`source` custom definitions are excluded from rendering.
2. `Занятия` — preferred schedule with an always-visible actual-lesson date tray + expandable Month/Week/Day calendar; no duplicate upcoming/past lists.
3. `Оплаты` — personal account, income/expense, actual payments, obligations/installments.
4. `Абонементы` — issued subscriptions and commercial snapshots.
5. `История и задачи` — chronological audit/user history and canonical tasks.
6. `Контакты` — contacts/representatives with actor-safe projection.
7. `Документы` — existing supported attachments/documents.

Sections unavailable by capability are absent. Direct section deep links route to a safe forbidden/fallback state without first rendering hidden data. The desktop role navigation rail stays mounted for the full client route; schedule/chat/task/direct-URL entry paths all canonicalize to the same `Clients` ancestor and preserve Lead/Student identity in the route presentation tail. On desktop, Preferred schedule stays expanded and immediately precedes the actual Month/Week/Day calendar; only that calendar viewport may be collapsed by default and it must not fetch while collapsed.

Lead and Student primary boards reuse the same toolbar component and geometry: title, stable local/server-safe search field, `Filters` expander and one capability-gated create FAB. Student filtering may expose a smaller filter set, but it must not use a visually separate header/action pattern.

`lead_sources` is the single acquisition-source catalog. Both Lead and Student store its UUID; conversion and subscription-driven conversion copy the exact UUID. New Lead/Student creation requires an active source. Migration preserves unmatched historical `adSource` labels as archived catalog entries before backfill, then removes duplicate configurable source fields.

### 7.2 Lessons section

Header: mode `Месяц / Неделя / День`, date navigation, effective branch/school selector, legend and `Добавить предпочтение` where allowed. Preferred schedule card/table is distinct from actual lesson facts.

Event hierarchy:

- selected client: success green surface/border plus persistent client marker;
- other actor-visible clients: neutral gray, lower emphasis;
- trial: separate gold marker;
- lifecycle/reservation: icon/text/token independent from client highlight;
- conflict: warning/danger outline and accessible label, never color alone.

Viewport query is bounded by visible date range and scope. Clicking an event opens lesson quick view; typed links continue to full entity routes.

### 7.3 Payments section

Desktop: balance summary and payment actions above a filterable transaction/obligation table. Mobile: summary cards followed by chronological list; filters in sheet. `Добавить оплату` opens a primary route on compact and a large routed workspace surface on desktop.

The long `Поступления и списания` and `Рассрочки и обязательства` groups are independently collapsed by default on every width; a typed deep link may expand the matching record group.

Form groups:

- Identity: date, invoice/receipt identifier, client.
- Scope: default client branch; school only if operation/capability permits.
- Amount: positive money input, currency, payment method, status.
- Commercial terms: typed percent/fixed discount, surcharge, installment plan with reason.
- Responsibility: who added, who accepted, accepted date.
- Comment and reconciliation preview.

Footer shows resulting balance/obligation effect before submit. Retry reuses idempotency metadata and preserves all input.

### 7.4 Tasks

Header has one `Создать задачу` primary action. View selector (`Мои`, `Команда`, permitted branch/school), filters and list/board modes share one provider/model. Old and new entry points resolve to this route until deletion. Recipient preview clearly separates fixed recipients from dynamic scope.

### 7.5 Unified dashboard

Sticky/shared filter bar owns period and effective scope. Sections render independently: operational summary, clients/funnel, lessons/utilization, tasks, permitted finance. Each card supports an explainable drilldown using the exact normalized filter. Manager layout omits school finance rather than showing locked cards.

### 7.6 Configurable CRM

Three-pane desktop flow where width permits: objects/categories → fields/options → preview/properties. Compact flow uses nested routes with Back and breadcrumbs/path menu. Draft status and scope inheritance are always visible. Publish requires impact preview; rollback creates a new revision and never mutates history.

## 8. Form standard

| Element | Rule |
|---|---|
| Label | Persistent above/alongside field; placeholder is example, not label |
| Required | Text/marker plus validation; not color alone |
| Help | Short inline text or labelled tooltip; never unlabeled `?` icon |
| Validation | On blur/submit as appropriate; field error preserved through retry |
| Async select | Loading/empty/error/retry within control; selected typed ref remains visible |
| Saving | Primary action disabled with progress and stable label; duplicate submit blocked |
| Success | Toast/inline confirmation and deterministic navigation choice |
| Conflict | Explain stale version, preserve input, offer reload/compare/retry |
| Cancel/Back | Save/Discard/Cancel if dirty; same contract on all exit paths |

### 8.1 Business-reference constructors

- Teacher create/edit requires one or more active branches and one or more
  disciplines from the union of those branches' active discipline catalogs.
  `specialization` is a compatibility projection derived from selected
  discipline labels and is never a second editable field. Create also requires
  email/password and atomically creates an active `teacher` app user, profile,
  Teacher, branch/discipline links and `user_crm_links` row.
- Staff create/edit requires one or more branches and a canonical business role.
  `staff_members.role` describes the operational entity and remains editable;
  `app.users.role` controls application access and is changed only by the access
  management flow after creation. Staff create requires email and password,
  hashes the password through the existing PasswordService, and atomically
  creates the active user, profile, staff entity, branch assignments and
  `user_crm_links` record. The selected staff role seeds the initial access role;
  later staff-role edits never mutate `app.users.role` implicitly.
- Existing Teacher/Staff records without app access expose one provision-access
  action. It hashes the supplied password and atomically upgrades the linked
  technical user or creates the missing user/profile/link. Existing app
  accounts are immutable through this action and duplicate provisioning fails.
- Group create requires branch, teacher and room. Teacher choices are active
  assignments of the selected branch; room choices belong to that branch. The
  server validates the same effective tuple on create/update.
- Rooms are managed from their owning Branch card, not a parallel organization
  tab. Branch and capacity validation are explicit before submit and on API.
- Async catalog failure/empty states block submit with an actionable explanation.
  Direct API calls enforce the same scope/reference rules transactionally.
- The unified `Варианты для полей` catalog is the only UI that creates select
  values; legacy comma-separated inline option editors are not production code.

## 9. Content and action language

- Buttons use verbs and objects: `Добавить оплату`, `Сохранить предпочтение`, `Перенести занятие`.
- Avoid generic `ОК`, ambiguous plus icons and unlabeled edit/delete icons.
- One create action per surface; FAB and header create button never coexist.
- Confirmation describes the object and impact, not merely `Вы уверены?`.
- Empty states explain whether data is absent, filtered out or inaccessible.
- Error messages state what happened, what was preserved and the next safe action.

## 10. Component states

### 10.1 `MagicContextBar`

- default: Back/Forward states, breadcrumb trail, current title, action slot;
- compact desktop: overflowed crumbs/actions;
- focus/hover: visible without layout jump;
- loading title: stable skeleton, Back remains usable;
- stale/forbidden parent: remove link and use safe fallback title;
- dirty: current tab/title shows dot; leaving invokes shared decision.

### 10.2 `MagicDraggableSheet`

- partial, near-full and full extents;
- content-loading skeleton;
- keyboard-open extent correction;
- nested-dialog/menu priority;
- dirty close interception;
- screen-reader title and current expanded/collapsed state.

### 10.3 `MagicPageState`

- loading skeleton shaped like expected content;
- empty explanation + at most one primary next action;
- error summary + retry, input preserved;
- forbidden actor-safe explanation + safe navigation action;
- partial error scoped to section, not full-page replacement.

## 11. Responsive behavior matrix

| Pattern | Compact `<600` | Medium `600–839` | Expanded `840–1199` | Large `>=1200` |
|---|---|---|---|---|
| Global nav | Bottom/top | Rail | Sidebar | Sidebar |
| Workspace tabs | No | No | Yes | Yes |
| Breadcrumbs | Back + title/path menu | Back + title/path menu | Collapsed context bar | Full context bar |
| Client card | Route | Route/single pane | Full workspace | Full workspace/master detail optional |
| Forms | 1 column | 1–2 by semantic group | 2 where scan improves | 2–3 only for short related fields |
| Calendar | Mode-specific viewport | Wider single viewport | Full grid | Full grid + side detail optional |
| Tables | Cards/list or horizontal viewport | Adaptive table | Dense table | Dense table |
| Quick view | Draggable sheet | Draggable/side sheet | Side/large sheet | Side/large sheet |

## 12. Acceptance matrix

Every migrated route must pass:

| Axis | Required values |
|---|---|
| Role | Every role with allow and at least one deny case |
| Scope | Client branch, alternate permitted branch, school when supported, forbidden scope |
| Width | 360, 600, 840, 1200+ representative widths |
| Input | Touch, mouse-only, keyboard-only, screen reader smoke |
| State | Loading, data, empty, validation, network error/retry, forbidden, conflict where versioned |
| Navigation | In-app link, direct deep link, UI Back, system/predictive Back, breadcrumb, tab restore where desktop |
| Data | API call parity, no duplicate mutation, actor-safe payload, result reconciliation |

Owner UAT records route, role, scope, device, start state, actions, expected/actual, screenshot/video, API trace and resulting data evidence.
