# Staff Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Реализовать все основные рабочие разделы Admin, Manager, Director и system_admin: Обзор, Расписание, Клиенты и Задачи.

**Architecture:** Каждый раздел является отдельным route family и использует единый scenario store. Все модальные и боковые поверхности регистрируются отдельно, поэтому переходы из Month, Week, обоих Day, карточки клиента и задач проверяются одинаково.

**Tech Stack:** React 19, TypeScript, Vitest, Testing Library, CSS Grid.

**Spec:** `docs/superpowers/specs/2026-08-16-full-ui-prototype-coverage-design.md`

## Global Constraints

- Сначала выполнить планы foundation и role portals.
- Admin видит только Чат, Расписание, Клиенты и Задачи.
- Manager не получает school-finance и директорские mutation controls.
- Геометрия и responsive-режимы повторяют Flutter-источники; меняется только палитра.
- Все lesson write paths используют один визуальный analyzer и один набор русских конфликтов.

---

### Task 1: Manager overview and KPI deep links

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/staff/OverviewScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/staff/overviewManifest.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/staff/OverviewScreen.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/staff/staff.css`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: branch, period, attention items and KPI scenario data.
- Produces: `overview.default`, `overview.loading`, `overview.empty`, `overview.error`; canonical KPI navigation.

- [ ] **Step 1: Write failing role and deep-link tests**

```tsx
it('opens schedule conflicts from the attention panel', async () => {
  const { user } = renderPrototype('overview.default', { role: 'director' })
  await user.click(screen.getByRole('button', { name: /Конфликты расписания.*2/ }))
  expect(readCatalogLocation(window.location.search).screenId).toBe('schedule.week.conflicts')
})

it('hides school finance for manager', () => {
  renderPrototype('overview.default', { role: 'manager' })
  expect(screen.queryByText('Выручка')).not.toBeInTheDocument()
  expect(screen.queryByText('Ожидаемые платежи')).not.toBeInTheDocument()
})
```

- [ ] **Step 2: Run tests to prove they fail**

Run: `npm test -- src/screens/staff/OverviewScreen.test.tsx`

Expected: FAIL because overview route family is not extracted.

- [ ] **Step 3: Implement overview filters and links**

Support `7 дней`, `Месяц`, `Квартал`, branch select, attention rows and all
existing KPI cards. Each card must declare an expected manifest route or have
no click affordance.

- [ ] **Step 4: Run tests, build and commit**

Run: `npm test -- src/screens/staff/OverviewScreen.test.tsx && npm run build`

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/staff design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover staff overview surfaces"
```

### Task 2: Schedule views, search and filters

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/ScheduleScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/MonthView.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/WeekView.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/DayByRoomsView.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/DayByTeachersView.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/ScheduleFiltersSheet.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/ScheduleSearchDialog.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/scheduleViews.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/schedule.css`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: scenario branches, rooms, teachers, lessons and current filters.
- Produces: `schedule.month`, `schedule.week`, `schedule.day.rooms`, `schedule.day.teachers`, `schedule.search`, `schedule.filters`, `schedule.timezone-warning`.

- [ ] **Step 1: Write failing view geometry tests**

```tsx
it.each([
  ['schedule.month', 'month-grid'],
  ['schedule.week', 'week-seven-columns'],
  ['schedule.day.rooms', 'day-room-columns'],
  ['schedule.day.teachers', 'teacher-horizontal-timeline'],
])('renders the canonical %s surface', (screenId, testId) => {
  renderPrototype(screenId, { role: 'director' })
  expect(screen.getByTestId(testId)).toBeInTheDocument()
})
```

- [ ] **Step 2: Run schedule view tests to prove they fail**

Run: `npm test -- src/screens/schedule/scheduleViews.test.tsx`

Expected: FAIL because the modular schedule views do not exist.

- [ ] **Step 3: Implement exact toolbar and responsive variants**

Include title, date range, search, filters, refresh, create, Month/Week/Day,
date navigation, branch select, day mode row, legend and availability. Compact
mode uses the Flutter-equivalent collapsed search/filter controls.

- [ ] **Step 4: Test search and filter preservation**

```tsx
it('keeps view, date and search text after opening a lesson', async () => {
  const { user } = renderPrototype('schedule.day.rooms', { role: 'director' })
  await user.type(screen.getByPlaceholderText('Поиск'), 'Анна')
  await user.click(screen.getByRole('button', { name: /Вокал.*Анна/ }))
  expect(readCatalogLocation(window.location.search)).toMatchObject({ screenId: 'lesson.details' })
  await user.click(screen.getByRole('button', { name: 'Назад' }))
  expect(screen.getByPlaceholderText('Поиск')).toHaveValue('Анна')
})
```

Add one parameterized test that enters the production examples for Lead,
Student, Teacher, Room and exact-date Lesson and asserts the matching schedule
result without resetting view, date or filters.

- [ ] **Step 5: Run tests and commit**

Run: `npm test -- src/screens/schedule/scheduleViews.test.tsx && npm run build`

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/schedule design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover all schedule views"
```

### Task 3: Lesson editor, decisions and conflict inspector

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/LessonEditor.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/LessonDetailsSheet.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/LessonDecisionFlow.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/ConflictInspector.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/RecurringPlanEditor.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/schedule/lessonFlows.test.tsx`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: lesson draft, settlement catalog, teacher pay catalog, subscription sources and constraint preview.
- Produces: `lesson.create`, `lesson.details`, `lesson.edit`, `lesson.reschedule`, `lesson.cancel`, `lesson.settlement-recovery`, `schedule.conflict-inspector`, `schedule.recurring-plan` and result states.

- [ ] **Step 1: Write failing financial-field and conflict tests**

```tsx
it('requires settlement, teacher pay and funding source separately', async () => {
  const { user } = renderPrototype('lesson.create', { role: 'director' })
  await user.click(screen.getByRole('button', { name: 'Проверить и создать' }))
  expect(screen.getByText('Выберите тип списания')).toBeInTheDocument()
  expect(screen.getByText('Выберите оплату преподавателю')).toBeInTheDocument()
  expect(screen.getByText('Выберите источник средств')).toBeInTheDocument()
})

it('keeps the complete draft after a commit conflict', async () => {
  const { user } = renderPrototype('lesson.create', { role: 'director', state: 'conflict' })
  await user.click(screen.getByRole('button', { name: 'Создать' }))
  expect(screen.getByDisplayValue('Анна Лебедева')).toBeInTheDocument()
  expect(screen.getByText('Время уже занято')).toBeInTheDocument()
})
```

- [ ] **Step 2: Run lesson flow tests to prove they fail**

Run: `npm test -- src/screens/schedule/lessonFlows.test.tsx`

Expected: FAIL because canonical lesson flows are not present.

- [ ] **Step 3: Implement shared preview and inspector**

All one-time and recurring entry points must render the same grouped teacher,
room, student, group and branch conflicts. Suggestions include free room,
nearest time, available teacher and combined ranked variants. The UI must not
commit while blocking conflicts remain.

- [ ] **Step 4: Implement reschedule, cancel and recurring plan states**

Reschedule and cancel show exact preview, reason, version and confirm stages.
Recurring Plan supports multiple rows, per-row teacher/room, group participant
subscriptions, edit, active/ended state and impact preview.

- [ ] **Step 5: Run tests, build and commit**

Run: `npm test -- src/screens/schedule && npm run build`

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/schedule design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover lesson and recurring schedule flows"
```

### Task 4: Client boards and canonical client card

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/clients/ClientBoardsScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/clients/ClientForm.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/clients/ClientCardScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/clients/ClientHistorySection.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/clients/ClientContactsSection.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/clients/ClientLifecycleFlow.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/clients/clientSurfaces.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/clients/clients.css`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: shared Lead/Student field definitions, board funnels and scenario clients.
- Produces: boards, create/edit forms, Lead/Student card routes, history tabs and lifecycle overlays.

- [ ] **Step 1: Write failing board and card tests**

```tsx
it('opens one scrollable Student card with the Payments section', async () => {
  const { user } = renderPrototype('clients.students', { role: 'director' })
  await user.click(screen.getByRole('button', { name: /Алиса Воронцова/ }))
  expect(screen.getByRole('heading', { name: 'Алиса Воронцова' })).toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'Оплаты' })).toBeInTheDocument()
  expect(screen.getByTestId('client-card-scroll-canvas')).toBeInTheDocument()
})
```

- [ ] **Step 2: Run tests to prove they fail**

Run: `npm test -- src/screens/clients/clientSurfaces.test.tsx`

Expected: FAIL because the boards and card are not modular manifest routes.

- [ ] **Step 3: Implement boards, forms and unified card**

Implement Lead and Student funnels, search, existing filters, notifications,
all configured field types, status transitions, loss reason, responsibility,
conversion, duplicate/merge/undo. The card is one scroll canvas with horizontal
section navigation and Student-only Payments.

- [ ] **Step 4: Implement history, contacts and lifecycle**

History contains Tasks, Comments and History. Contacts contains Family,
representatives, payer and application access. Documents have no invented upload
action. Archive uses preview, blockers, reason and commit result.

- [ ] **Step 5: Run tests, build and commit**

Run: `npm test -- src/screens/clients && npm run build`

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/clients design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover client boards and cards"
```

### Task 5: Shared task list, calendar and editor

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/tasks/TasksScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/tasks/TaskCalendar.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/tasks/TaskEditorSheet.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/tasks/TaskDetailsSheet.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/tasks/tasks.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/tasks/tasks.css`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: shared task scenario data and recipient preview.
- Produces: `tasks.list`, `tasks.calendar`, `task.create`, `task.edit`, `task.details`, task error/retry states.

- [ ] **Step 1: Write failing task behavior tests**

```tsx
it('opens a prefilled editor for an existing task', async () => {
  const { user } = renderPrototype('tasks.list', { role: 'director' })
  await user.click(screen.getAllByRole('button', { name: 'Изменить' })[0])
  expect(screen.getByRole('dialog', { name: 'Изменить задачу' })).toBeInTheDocument()
  expect(screen.getByLabelText('Название')).toHaveValue('Позвонить по заявке с сайта')
})

it('shows Admin defaults Мои задачи and Сегодня', () => {
  renderPrototype('tasks.list', { role: 'admin' })
  expect(screen.getByLabelText('Область')).toHaveValue('Мои задачи')
  expect(screen.getByRole('button', { name: 'Сегодня' })).toHaveAttribute('aria-pressed', 'true')
})
```

- [ ] **Step 2: Run tests to prove they fail**

Run: `npm test -- src/screens/tasks/tasks.test.tsx`

Expected: FAIL because the editor and canonical defaults are incomplete.

- [ ] **Step 3: Implement list, calendar, create, edit and details**

Support four states, search, priority, scope, Today, calendar, all-day and
interval dates, person/branch/school recipients, exact preview, reminder time,
details/history, close and retry without draft loss.

- [ ] **Step 4: Run the staff operations gate**

Run: `npm test -- src/screens/staff src/screens/schedule src/screens/clients src/screens/tasks && npm run build`

Expected: all staff operations tests PASS and build exits 0.

- [ ] **Step 5: Commit the staff milestone**

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/tasks design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover shared task workflows"
```
