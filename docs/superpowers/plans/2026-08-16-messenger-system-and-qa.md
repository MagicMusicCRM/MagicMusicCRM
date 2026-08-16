# Messenger System and QA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Завершить покрытие чатов, связанных сущностей, обновлений и системных состояний, затем доказать полноту автоматическим обходом манифеста.

**Architecture:** Messenger, entity routes and system overlays remain independent route families that reuse product shell and scenario state. Final QA derives test cases from `screenManifest`, so a registered surface cannot silently escape the route, action and console checks.

**Tech Stack:** React 19, TypeScript, Vitest, Testing Library, Playwright Test, Vite.

**Spec:** `docs/superpowers/specs/2026-08-16-full-ui-prototype-coverage-design.md`

## Global Constraints

- Выполнять после остальных четырёх планов.
- Не отправлять настоящие сообщения, файлы, письма, push или update installer.
- UI не показывает raw exceptions, токены, пароли или настоящие персональные данные.
- Update Center не содержит кнопку `Скачать вручную`.
- Итог `100%` допускается только при manifest, interaction, build и browser gates.

---

### Task 1: Messenger, groups, channels and notifications

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/messenger/MessengerScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/messenger/ConversationScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/messenger/MessageComposer.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/messenger/ConversationEditor.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/messenger/NotificationsScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/messenger/messenger.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/messenger/messenger.css`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: conversation, message, participant, permission and notification scenarios.
- Produces: chat list, conversation types, message actions, group/channel editor and notification routes.

- [ ] **Step 1: Write failing message and permission tests**

```tsx
it.each(['Текст', 'Изображение', 'Файл', 'Голосовое сообщение'])('adds %s to the local conversation', async (kind) => {
  const { user } = renderPrototype('messenger.conversation', { role: 'director' })
  await user.click(screen.getByRole('button', { name: kind }))
  await user.click(screen.getByRole('button', { name: 'Отправить' }))
  expect(screen.getByTestId('message-list')).toHaveTextContent(kind)
})

it('prevents a read-only channel member from sending', () => {
  renderPrototype('messenger.channel', { role: 'teacher', state: 'readonly' })
  expect(screen.queryByRole('textbox', { name: 'Сообщение' })).not.toBeInTheDocument()
  expect(screen.getByText('В этом канале доступно только чтение')).toBeInTheDocument()
})
```

- [ ] **Step 2: Run tests to prove they fail**

Run: `npm test -- src/screens/messenger/messenger.test.tsx`

Expected: FAIL because messenger route family is incomplete.

- [ ] **Step 3: Implement conversations and message actions**

Cover folders, search, unread count, direct, Administration, group, channel and
support conversations; text/image/file/voice; reply, forward, edit, delete,
reaction, pin and read state; loading, empty, chat error, message error and retry.

- [ ] **Step 4: Implement lifecycle and notifications**

Cover group/channel create and edit, participants, role/user ACL, leave,
archive/restore, notification list/preferences and navigation from Lead, Task and
Lesson notifications.

- [ ] **Step 5: Run tests, build and commit**

Run: `npm test -- src/screens/messenger && npm run build`

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/messenger design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover messenger and notification surfaces"
```

### Task 2: Entity routes and workspace history

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/entities/entityRoutes.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/entities/EntitySurface.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/entities/EntityStateScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/entities/entityRoutes.test.tsx`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/shell/ProductShell.tsx`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: manifest location and scenario entity records.
- Produces: `resolveEntitySurface(entityType, entityId, role)` and routes for Lead, Student, Teacher, Staff, Lesson, Group, Room, Branch, Series, Task, Payment and User.

```ts
export type EntityType = 'lead' | 'student' | 'teacher' | 'staff' | 'lesson' | 'group' | 'room' | 'branch' | 'series' | 'task' | 'payment' | 'user'
export interface EntityResolution { screenId: string; state: ScreenStateId }
export function resolveEntitySurface(entityType: EntityType, entityId: string, role: Role): EntityResolution
```

- [ ] **Step 1: Write failing entity-resolution tests**

```ts
it.each([
  ['student', 'student-1', 'clients.student-card'],
  ['teacher', 'teacher-1', 'entity.teacher'],
  ['lesson', 'lesson-1', 'lesson.details'],
  ['group', 'group-1', 'entity.group'],
  ['payment', 'payment-1', 'entity.payment'],
])('resolves %s to %s', (type, id, expected) => {
  expect(resolveEntitySurface(type, id, 'director').screenId).toBe(expected)
})
```

- [ ] **Step 2: Run tests to prove they fail**

Run: `npm test -- src/screens/entities/entityRoutes.test.tsx`

Expected: FAIL because entity route resolver does not exist.

- [ ] **Step 3: Implement entity surfaces and failure states**

Support canonical breadcrumb and content for all twelve entity types plus
unknown, deleted, forbidden and safe error states. A role cannot resolve an
entity surface that production capabilities hide.

- [ ] **Step 4: Test tab, Back and Forward preservation**

```tsx
it('restores the prior filter and draft after Back', async () => {
  const { user } = renderPrototype('clients.leads', { role: 'director' })
  await user.type(screen.getByPlaceholderText('Поиск'), 'София')
  await user.click(screen.getByRole('button', { name: /София Крылова/ }))
  await user.click(screen.getByRole('button', { name: 'Назад' }))
  expect(screen.getByPlaceholderText('Поиск')).toHaveValue('София')
})
```

- [ ] **Step 5: Run tests, build and commit**

Run: `npm test -- src/screens/entities src/shell && npm run build`

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/entities design_prototypes/magicmusic-light-design-lab/src/shell/ProductShell.tsx design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover linked entity workspace routes"
```

### Task 3: Update Center and universal page states

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/system/UpdateCenter.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/system/StaffProfileScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/system/UnsavedChangesDialog.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/system/PageState.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/system/systemScreens.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/system/system.css`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: installed version, release history, update state and retry callback.
- Produces: update center states, staff profile and auth-method routes, unsaved-change confirmation and shared page-state component.

- [ ] **Step 1: Write failing update-copy tests**

```tsx
it('shows the version button and never renders manual download', async () => {
  renderPrototype('updates.available', { role: 'director' })
  expect(screen.getByRole('button', { name: /1\.5\.14/ })).toBeInTheDocument()
  expect(screen.queryByText('Скачать вручную')).not.toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'Обновить и перезапустить' })).toBeInTheDocument()
})

it.each(['offline', 'invalid-response', 'configuration-error', 'install-error'])('shows safe update error %s', (state) => {
  renderPrototype(`updates.${state}`, { role: 'director' })
  expect(screen.queryByText(/Exception|Stack trace|HTTP 5\d\d/)).not.toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'Повторить' })).toBeInTheDocument()
})
```

- [ ] **Step 2: Run tests to prove they fail**

Run: `npm test -- src/screens/system/systemScreens.test.tsx`

Expected: FAIL because all update states are not registered.

- [ ] **Step 3: Implement updates and shared states**

Cover installed, checking, up-to-date, available, history, installing, restart,
offline, invalid response, configuration and install errors. Golden dot appears
only on the bottom-left version control. Add shared loading, empty, error,
forbidden and retry visuals without replacing screen-specific text.

- [ ] **Step 4: Implement the current-user profile**

Register `profile.staff` and `profile.auth-methods`. Cover photo, name, surname,
phone, role, birthday, login methods and legal documents. Director and
system_admin profile routes must not reveal managed passwords for other people;
that action remains only in `settings.users.access`. Register the root emergency
access surface only for system_admin.

- [ ] **Step 5: Implement unsaved changes confirmation**

Close tab and true route leave can open `Сохранить изменения?` with `Остаться`,
`Не сохранять` and `Сохранить`. Plain tab switching must preserve the draft and
must not open confirmation.

- [ ] **Step 6: Run tests, build and commit**

Run: `npm test -- src/screens/system && npm run build`

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/system design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover updates and universal UI states"
```

### Task 4: Manifest coverage and browser acceptance gate

**Files:**
- Modify: `design_prototypes/magicmusic-light-design-lab/package.json`
- Modify: `design_prototypes/magicmusic-light-design-lab/vite.config.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/playwright.config.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/catalog/coverageReport.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/catalog/coverageReport.test.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/tests/manifest-routes.spec.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/tests/required-actions.spec.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/tests/source-inventory.spec.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/tests/ui-copy.spec.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/SCREEN-COVERAGE.md`
- Modify: `design_prototypes/magicmusic-light-design-lab/README.md`

**Interfaces:**
- Consumes: complete `screenManifest` and running Vite app.
- Produces: `CoverageReport`, `buildCoverageReport(inventory, results)`, `npm run test:e2e`, route/action screenshots and `SCREEN-COVERAGE.md`.

```ts
export interface ScreenCheckResult {
  screenId: string
  routePassed: boolean
  actionsPassed: boolean
  consoleErrors: number
}

export interface CoverageReport {
  total: number
  passedRoutes: number
  passedActions: number
  unhandledActions: number
  consoleErrors: number
  percent: number
}

export function buildCoverageReport(inventory: SurfaceInventoryEntry[], results: ScreenCheckResult[]): CoverageReport
```

- [ ] **Step 1: Add Playwright Test and scripts**

Add `@playwright/test` to `devDependencies` and scripts:

```json
{
  "test:e2e": "playwright test",
  "test:all": "npm test && npm run build && npm run test:e2e"
}
```

Use base URL `http://127.0.0.1:4178` and `webServer.command = 'npm run dev'`.

- [ ] **Step 2: Write the failing coverage report test**

```ts
it('refuses 100 percent while any route or action is missing', () => {
  const report = buildCoverageReport([
    { id: 'overview.default', title: 'Сводка', family: 'overview', sourceFiles: ['lib/features/manager/presentation/widgets/manager_overview_widget.dart'], requiredRoles: ['director'], requiredViewports: ['desktop'] },
    { id: 'schedule.week', title: 'Неделя', family: 'schedule', sourceFiles: ['lib/features/admin/presentation/widgets/schedule_widget_views_a.dart'], requiredRoles: ['director'], requiredViewports: ['desktop'] },
  ], [
    { screenId: 'overview.default', routePassed: true, actionsPassed: false, consoleErrors: 0 },
  ])
  expect(report.percent).toBeLessThan(100)
  expect(report.unhandledActions).toBe(1)
})
```

- [ ] **Step 3: Run the report test to prove it fails**

Run: `npm test -- src/catalog/coverageReport.test.ts`

Expected: FAIL because coverage report does not exist.

- [ ] **Step 4: Implement route and action derived tests**

`manifest-routes.spec.ts` iterates every role, viewport, screen and state,
opens its permanent URL, asserts `[data-screen-id]`, heading and no console error,
then saves `qa-screens/<screenId>/<role>-<state>-<viewport>.png`.

`required-actions.spec.ts` iterates `requiredActions`, clicks the labelled
control and asserts the expected screen id or state.

`source-inventory.spec.ts` asserts every audited inventory id has a matching
manifest entry, every manifest id belongs to the inventory, and every
`sourceFiles` path exists relative to the MagicMusicCRM repository root.

`ui-copy.spec.ts` rejects `Snapshot`, `Schedule analyzer`, `Schedule Analyzer`,
`Скачать вручную`, Unicode en dash and Unicode em dash in product canvas text.

- [ ] **Step 5: Implement and display coverage report**

The report contains total/implemented/route-checked/action-checked counts,
unhandled actions, console errors and applicable visual comparisons. The UI may
show `100%` only when every denominator is complete and both error counts are 0.

- [ ] **Step 6: Run the full automated gate**

Run: `npm run test:all`

Expected: unit tests PASS, TypeScript/Vite build exits 0, every Playwright route
and required action PASS, console errors 0.

- [ ] **Step 7: Perform visual comparison with Release evidence**

For each available production reference, use the same viewport and state, place
reference and prototype screenshots into one comparison image, inspect layout,
overflow, type, borders and radii, and record the result in `SCREEN-COVERAGE.md`.

- [ ] **Step 8: Commit the completed acceptance gate**

```bash
git add design_prototypes/magicmusic-light-design-lab/package.json design_prototypes/magicmusic-light-design-lab/package-lock.json design_prototypes/magicmusic-light-design-lab/playwright.config.ts design_prototypes/magicmusic-light-design-lab/src/catalog design_prototypes/magicmusic-light-design-lab/tests design_prototypes/magicmusic-light-design-lab/SCREEN-COVERAGE.md design_prototypes/magicmusic-light-design-lab/README.md
git commit -m "test: prove complete UI prototype coverage"
```
