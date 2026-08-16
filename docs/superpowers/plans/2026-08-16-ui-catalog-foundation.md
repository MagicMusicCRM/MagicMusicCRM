# UI Catalog Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Создать типизированный каталог экранов, постоянные URL и ролевой shell, на которых строится полное покрытие дизайн-стенда.

**Architecture:** `screenManifest` является единственным реестром поверхностей и обязательных действий. `ScenarioProvider` хранит выбранную роль, экран, состояние и локальные данные, а `ProductShell` и служебный `ScreenCatalog` читают один реестр.

**Tech Stack:** React 19, TypeScript 5.9, Vite 7, Vitest, Testing Library, jsdom.

**Spec:** `docs/superpowers/specs/2026-08-16-full-ui-prototype-coverage-design.md`

## Global Constraints

- Изменять только `design_prototypes/magicmusic-light-design-lab/` и документы стенда.
- Не изменять Flutter, NestJS, PostgreSQL или production release.
- UI-текст стенда только русский, без длинных тире и внутренних английских названий.
- Каждый экран имеет стабильный `screenId`, source files, роли, viewport, состояния и обязательные действия.
- Любая видимая кнопка выполняет переход, меняет состояние, открывает поверхность или явно disabled с причиной.
- Служебный каталог не считается частью product canvas и должен сворачиваться.

---

### Task 1: Test harness and manifest contract

**Files:**
- Modify: `design_prototypes/magicmusic-light-design-lab/package.json`
- Modify: `design_prototypes/magicmusic-light-design-lab/vite.config.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/test/setup.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.test.ts`

**Interfaces:**
- Consumes: existing Vite React application.
- Produces: `npm test`, `npm run test:coverage`, jsdom setup, failing contract for `screenManifest`.

- [ ] **Step 1: Add test dependencies and scripts**

Add `vitest`, `@testing-library/react`, `@testing-library/jest-dom`,
`@testing-library/user-event` and `jsdom` to `devDependencies`. Add scripts:

```json
{
  "test": "vitest run",
  "test:watch": "vitest",
  "test:coverage": "vitest run --coverage"
}
```

Extend `vite.config.ts`:

```ts
/// <reference types="vitest/config" />
export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    css: true,
  },
  server: { port: 4178, strictPort: true },
})
```

- [ ] **Step 2: Write the failing manifest test**

```ts
import { describe, expect, it } from 'vitest'
import { screenManifest, validateManifest } from './screenManifest'

describe('screenManifest', () => {
  it('contains only complete and unique screen entries', () => {
    expect(validateManifest(screenManifest)).toEqual([])
    expect(new Set(screenManifest.map((item) => item.id)).size).toBe(screenManifest.length)
  })
})
```

- [ ] **Step 3: Install and prove the test fails**

Run: `npm install && npm test -- src/catalog/screenManifest.test.ts`

Expected: FAIL because `./screenManifest` does not exist.

- [ ] **Step 4: Commit the red test harness**

```bash
git add design_prototypes/magicmusic-light-design-lab/package.json design_prototypes/magicmusic-light-design-lab/package-lock.json design_prototypes/magicmusic-light-design-lab/vite.config.ts design_prototypes/magicmusic-light-design-lab/src/test/setup.ts design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.test.ts
git commit -m "test: add UI catalog contract harness"
```

### Task 2: Typed manifest and validation

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/catalog/types.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/catalog/surfaceInventory.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.test.ts`

**Interfaces:**
- Consumes: no runtime state.
- Produces: `Role`, `Viewport`, `SurfaceKind`, `ScreenStateId`, `SurfaceInventoryEntry`, `ScreenEntry`, `surfaceInventory`, `screenManifest`, `getScreenEntry(id)` and `validateManifest(entries, sourceExists)`.

- [ ] **Step 1: Define the exact public types**

```ts
export type Role = 'client' | 'teacher' | 'admin' | 'manager' | 'director' | 'system_admin'
export type Viewport = 'desktop' | 'compact'
export type SurfaceKind = 'page' | 'route' | 'dialog' | 'sheet' | 'menu' | 'state'
export type ScreenStateId = 'content' | 'loading' | 'empty' | 'error' | 'forbidden' | 'offline' | 'readonly' | 'archived' | 'conflict' | 'stale'

export interface ScreenActionContract {
  id: string
  label: string
  expectedScreenId?: string
  expectedState?: ScreenStateId
}

export interface ScreenEntry {
  id: string
  title: string
  family: string
  roles: Role[]
  surface: SurfaceKind
  sourceFiles: string[]
  entryFrom: string[]
  states: ScreenStateId[]
  requiredActions: ScreenActionContract[]
  viewports: Viewport[]
}

export interface SurfaceInventoryEntry {
  id: string
  title: string
  family: string
  sourceFiles: string[]
  requiredRoles: Role[]
  requiredViewports: Viewport[]
}

export type SourceExists = (path: string) => boolean
export function validateManifest(entries: ScreenEntry[], sourceExists: SourceExists = () => true): string[]
```

- [ ] **Step 2: Build the complete source inventory**

Create `surfaceInventory` before feature implementation. Its ids must cover the
fourteen surface groups in Spec section 6 with these stable prefixes:
`auth`, `client`, `teacher`, `messenger`, `overview`, `schedule`, `lesson`,
`clients`, `commerce`, `tasks`, `analytics`, `settings`, `entity`, `updates`,
`profile` and `system`. Include every dialog, sheet and visually distinct state
named in the spec, with its actual Flutter source files and applicable roles and
viewports. Inventory entries are not rendered until a matching `ScreenEntry`
exists, so the catalog can report pending coverage honestly.

- [ ] **Step 3: Implement validation and a seed manifest**

`validateManifest` must return Russian diagnostics for empty ids, duplicate ids,
missing source files, empty roles, states or viewports, duplicate action ids and
an `expectedScreenId` that is absent from the same manifest.

Seed entries must cover `overview.default`, `schedule.week`, `clients.leads`,
`tasks.list`, `analytics.overview`, `settings.organization`, `updates.center`,
`auth.login`, `client.lessons` and `teacher.schedule` with real source paths.

- [ ] **Step 4: Add inventory and negative validation cases**

```ts
it('reports duplicate ids and broken action targets', () => {
  const broken = [
    { ...screenManifest[0], id: 'duplicate' },
    { ...screenManifest[0], id: 'duplicate', requiredActions: [{ id: 'open', label: 'Открыть', expectedScreenId: 'missing' }] },
  ]
  expect(validateManifest(broken).join('\n')).toContain('Повторяется идентификатор duplicate')
  expect(validateManifest(broken).join('\n')).toContain('Не найден экран missing')
})

it('keeps every implemented screen inside the audited inventory', () => {
  const inventoryIds = new Set(surfaceInventory.map((item) => item.id))
  expect(screenManifest.filter((item) => !inventoryIds.has(item.id))).toEqual([])
  expect(new Set(surfaceInventory.map((item) => item.id)).size).toBe(surfaceInventory.length)
})
```

- [ ] **Step 5: Run tests and typecheck**

Run: `npm test -- src/catalog/screenManifest.test.ts && npm run build`

Expected: manifest tests PASS and build exits 0.

- [ ] **Step 6: Commit the manifest core**

```bash
git add design_prototypes/magicmusic-light-design-lab/src/catalog
git commit -m "feat: add typed screen manifest"
```

### Task 3: URL state and service catalog

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/catalog/urlState.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/catalog/urlState.test.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/catalog/ScreenCatalog.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/catalog/ScreenCatalog.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/catalog/catalog.css`

**Interfaces:**
- Consumes: `Role`, `Viewport`, `ScreenStateId`, `screenManifest`.
- Produces: `CatalogLocation`, `readCatalogLocation(search)`, `writeCatalogLocation(location)`, `ScreenCatalog`.

```ts
export interface CatalogLocation {
  role: Role
  screenId: string
  state: ScreenStateId
  viewport: Viewport
}

export function readCatalogLocation(search: string): CatalogLocation
export function writeCatalogLocation(location: CatalogLocation): string
```

- [ ] **Step 1: Write URL round-trip tests**

```ts
it('round-trips role, screen, state and viewport', () => {
  const input = { role: 'director', screenId: 'schedule.week', state: 'content', viewport: 'desktop' } as const
  expect(readCatalogLocation(writeCatalogLocation(input))).toEqual(input)
})

it('uses safe defaults for unknown values', () => {
  expect(readCatalogLocation('?role=hacker&screen=missing')).toEqual({
    role: 'director', screenId: 'overview.default', state: 'content', viewport: 'desktop',
  })
})
```

- [ ] **Step 2: Run the URL tests to prove they fail**

Run: `npm test -- src/catalog/urlState.test.ts`

Expected: FAIL because URL helpers do not exist.

- [ ] **Step 3: Implement URL helpers and catalog controls**

The catalog must provide labelled controls `Роль`, `Экран`, `Состояние`,
`Ширина`, a text search, family grouping, source-file disclosure, previous and
next screen buttons, and `Свернуть каталог`. Every change must use
`history.replaceState` and dispatch a local `catalog-location-change` event.

- [ ] **Step 4: Test catalog interaction**

```tsx
it('selects a screen and writes a stable URL', async () => {
  const user = userEvent.setup()
  const onChange = vi.fn()
  const initialLocation = { role: 'director', screenId: 'overview.default', state: 'content', viewport: 'desktop' } as const
  render(<ScreenCatalog location={initialLocation} onChange={onChange} />)
  await user.selectOptions(screen.getByLabelText('Экран'), 'schedule.week')
  expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ screenId: 'schedule.week' }))
})
```

Run: `npm test -- src/catalog`

Expected: all catalog tests PASS.

- [ ] **Step 5: Commit URL navigation and catalog**

```bash
git add design_prototypes/magicmusic-light-design-lab/src/catalog
git commit -m "feat: add persistent screen catalog navigation"
```

### Task 4: Role-aware product shell

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/shell/roleNavigation.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/shell/roleNavigation.test.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/shell/ProductShell.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/shell/ProductShell.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/shell/shell.css`

**Interfaces:**
- Consumes: `Role`, `ScreenEntry`, catalog location.
- Produces: `getRoleNavigation(role)`, `ProductShellProps`, product navigation and desktop tabs.

```ts
export interface RoleNavItem {
  id: string
  label: string
  screenId: string
}

export function getRoleNavigation(role: Role): RoleNavItem[]
```

- [ ] **Step 1: Lock the role navigation matrix in a failing test**

```ts
expect(getRoleNavigation('client').map((item) => item.label)).toEqual(['Чат', 'Занятия', 'Абонемент', 'Профиль'])
expect(getRoleNavigation('teacher').map((item) => item.label)).toEqual(['Чат', 'Расписание', 'Ученики'])
expect(getRoleNavigation('admin').map((item) => item.label)).toEqual(['Чат', 'Расписание', 'Клиенты', 'Задачи'])
expect(getRoleNavigation('manager').map((item) => item.label)).toEqual(['Чат', 'Обзор', 'Расписание', 'Клиенты', 'Задачи', 'Аналитика', 'Настройки'])
```

Director and system_admin must use the same visible top-level order as Manager;
their capabilities change nested actions, not the order.

- [ ] **Step 2: Run the shell test to prove it fails**

Run: `npm test -- src/shell/roleNavigation.test.ts`

Expected: FAIL because `getRoleNavigation` does not exist.

- [ ] **Step 3: Implement ProductShell**

`ProductShell` accepts:

```ts
export interface ProductShellProps {
  role: Role
  activeScreen: ScreenEntry
  viewport: Viewport
  onNavigate: (screenId: string) => void
  children: React.ReactNode
}
```

It must render desktop tabs, Back, Forward, role-correct primary navigation,
version control at bottom-left, a compact navigation variant and a single
`main` content region. Catalog controls must render outside this component.

- [ ] **Step 4: Verify hidden destinations are absent**

```tsx
const entry = screenManifest.find((item) => item.id === 'tasks.list')!
render(<ProductShell role="admin" activeScreen={entry} viewport="desktop" onNavigate={vi.fn()}>Экран</ProductShell>)
expect(screen.queryByRole('button', { name: 'Аналитика' })).not.toBeInTheDocument()
expect(screen.queryByRole('button', { name: 'Настройки' })).not.toBeInTheDocument()
expect(screen.getByRole('button', { name: 'Задачи' })).toBeInTheDocument()
```

Run: `npm test -- src/shell`

Expected: all shell tests PASS.

- [ ] **Step 5: Commit the shell**

```bash
git add design_prototypes/magicmusic-light-design-lab/src/shell
git commit -m "feat: add role-aware product shell"
```

### Task 5: Scenario provider and baseline App migration

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/scenarios/types.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/scenarios/seed.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/scenarios/ScenarioProvider.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/scenarios/ScenarioProvider.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/test/renderPrototype.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/ui/Button.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/ui/Badge.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/ui/Field.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/ui/Segmented.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/App.tsx`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/main.tsx`

**Interfaces:**
- Consumes: catalog location, manifest and shell.
- Produces: `ScenarioState`, `ScenarioAction`, `useScenario()`, `AppRouter` and a thin `App` composition root.

- [ ] **Step 1: Write scenario reset and mutation tests**

```tsx
function Probe() {
  const { state, dispatch } = useScenario()
  return <><output data-testid="open-count">{state.tasks.filter((task) => task.state === 'open').length}</output><button onClick={() => dispatch({ type: 'task.closed', taskId: 'task-1' })}>Закрыть задачу</button></>
}

it('resets mock state when the selected scenario changes', async () => {
  const user = userEvent.setup()
  const { rerender } = render(<ScenarioProvider scenarioId="tasks.list"><Probe /></ScenarioProvider>)
  await user.click(screen.getByRole('button', { name: 'Закрыть задачу' }))
  expect(screen.getByTestId('open-count')).toHaveTextContent('17')
  rerender(<ScenarioProvider scenarioId="tasks.list.error"><Probe /></ScenarioProvider>)
  expect(screen.getByTestId('open-count')).toHaveTextContent('18')
})
```

- [ ] **Step 2: Run the scenario test to prove it fails**

Run: `npm test -- src/scenarios/ScenarioProvider.test.tsx`

Expected: FAIL because the provider does not exist.

- [ ] **Step 3: Implement deterministic scenario state**

Use stable ids for branches, rooms, teachers, clients, lessons, tasks,
payments and subscriptions. Expose:

```ts
export interface ScenarioTask {
  id: string
  title: string
  state: 'open' | 'closed'
  dueAt: string
}

export interface ScenarioState {
  scenarioId: string
  revision: number
  tasks: ScenarioTask[]
  entities: Record<string, Record<string, unknown>>
  ui: Record<string, string | number | boolean>
}

export type ScenarioAction =
  | { type: 'scenario.replaced'; scenarioId: string }
  | { type: 'task.closed'; taskId: string }
  | { type: 'entity.updated'; entityType: string; entityId: string; patch: Record<string, unknown> }

export interface ScenarioContextValue {
  state: ScenarioState
  dispatch: React.Dispatch<ScenarioAction>
  reset: () => void
}
```

Do not use random values or current timestamps.

Create the shared test renderer used by all later plans:

```tsx
export interface RenderPrototypeOptions {
  role?: Role
  state?: ScreenStateId
  viewport?: Viewport
}

export function renderPrototype(screenId: string, options: RenderPrototypeOptions = {}) {
  const location: CatalogLocation = {
    role: options.role ?? 'director',
    screenId,
    state: options.state ?? 'content',
    viewport: options.viewport ?? 'desktop',
  }
  window.history.replaceState(null, '', writeCatalogLocation(location))
  return { user: userEvent.setup(), ...render(<App />) }
}
```

- [ ] **Step 4: Extract shared UI primitives and compose the new App**

Move only shared visual primitives out of the monolith. `App.tsx` must become a
composition root that reads URL state, mounts `ScreenCatalog`,
`ScenarioProvider`, `ProductShell` and `AppRouter`.

- [ ] **Step 5: Run the complete foundation gate**

Run: `npm test && npm run build`

Expected: all tests PASS and Vite build exits 0.

- [ ] **Step 6: Commit the foundation milestone**

```bash
git add design_prototypes/magicmusic-light-design-lab/src design_prototypes/magicmusic-light-design-lab/package.json design_prototypes/magicmusic-light-design-lab/package-lock.json design_prototypes/magicmusic-light-design-lab/vite.config.ts
git commit -m "feat: establish full-screen prototype foundation"
```
