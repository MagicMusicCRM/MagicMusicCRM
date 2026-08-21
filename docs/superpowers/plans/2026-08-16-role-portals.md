# Role Portals Implementation Plan

> **Latest owner scope:** visual click-through only. Buttons open the required
> surface; no mocked calculations, persistence, network requests or business engine.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Покрыть вход, клиентский кабинет и кабинет преподавателя всеми production-reachable экранами и состояниями.

**Architecture:** Ролевые кабинеты используют общий `ScenarioProvider`, manifest routing и shared messenger/lesson primitives. Каждая визуально отличимая поверхность получает отдельный manifest id, но общие данные остаются едиными.

**Tech Stack:** React 19, TypeScript, Vitest, Testing Library, Phosphor Icons.

**Spec:** `docs/superpowers/specs/2026-08-16-full-ui-prototype-coverage-design.md`

## Global Constraints

- Сначала выполнить `2026-08-16-ui-catalog-foundation.md`.
- Не добавлять поля, действия или статусы, которых нет в Flutter-источниках.
- Client не видит staff note, внутренние комментарии и чужие финансы.
- Teacher не видит commerce, контакты, staff note и неназначенных учеников.
- Все ошибки имеют безопасный русский текст и каноническое действие повтора.

---

### Task 1: Authentication and onboarding surfaces

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/auth/AuthScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/auth/authManifest.ts`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/auth/AuthScreen.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/auth/auth.css`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: `ScreenStateId`, `ScenarioContextValue`, `ScreenEntry`.
- Produces: manifest ids `auth.login`, `auth.otp`, `auth.password-reset`, `auth.registration`, `auth.onboarding`, `auth.legal-consent`, `auth.session-check`.

- [ ] **Step 1: Write failing route and interaction tests**

```tsx
it('moves from director login to email code', async () => {
  const { user } = renderPrototype('auth.login', { role: 'director' })
  await user.type(screen.getByLabelText('Почта'), 'director@magicmusic.ru')
  await user.type(screen.getByLabelText('Пароль'), 'correct-password')
  await user.click(screen.getByRole('button', { name: 'Войти' }))
  expect(readCatalogLocation(window.location.search).screenId).toBe('auth.otp')
})

it('keeps password recovery input after a delivery error', async () => {
  renderPrototype('auth.password-reset', { role: 'client', state: 'error' })
  expect(screen.getByLabelText('Почта')).toHaveValue('client@magicmusic.ru')
  expect(screen.getByRole('button', { name: 'Повторить' })).toBeInTheDocument()
})
```

- [ ] **Step 2: Run the tests to prove they fail**

Run: `npm test -- src/screens/auth/AuthScreen.test.tsx`

Expected: FAIL because the auth routes are not registered.

- [ ] **Step 3: Implement all auth states and transitions**

Implement Russian validation for wrong credentials, unavailable OTP delivery,
expired code, resend cooldown, password mismatch, missing legal consent and
safe session-check error. Registration and onboarding must be Client-only.

- [ ] **Step 4: Run auth tests and build**

Run: `npm test -- src/screens/auth && npm run build`

Expected: all auth tests PASS and build exits 0.

- [ ] **Step 5: Commit auth coverage**

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/auth design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover authentication and onboarding screens"
```

### Task 2: Client lessons and homework

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/client/ClientLessonsScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/client/ClientLessonDetails.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/client/ClientHomeworkScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/client/clientLessons.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/client/client.css`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: scenario lessons, homework assignments and common page states.
- Produces: `client.lessons.upcoming`, `client.lessons.history`, `client.homework`, `client.lesson.details`.

- [ ] **Step 1: Write failing tab and detail tests**

```tsx
it('opens the same lesson details from upcoming and history', async () => {
  const { user } = renderPrototype('client.lessons.upcoming', { role: 'client' })
  await user.click(screen.getByRole('button', { name: /Вокал.*16 августа/ }))
  expect(readCatalogLocation(window.location.search).screenId).toBe('client.lesson.details')
})

it.each(['loading', 'empty', 'error'] as const)('renders the %s lesson state', (state) => {
  renderPrototype('client.lessons.upcoming', { role: 'client', state })
  expect(screen.getByTestId(`page-state-${state}`)).toBeInTheDocument()
})
```

- [ ] **Step 2: Run the client lesson tests to prove they fail**

Run: `npm test -- src/screens/client/clientLessons.test.tsx`

Expected: FAIL because the client lesson screens do not exist.

- [ ] **Step 3: Implement lessons, details and homework**

The lesson surface must expose `Предстоящие`, `История`, `Задания`. Homework
must show assignment, lesson link, attachment, submitted state and safe file
failure. Client details contain only client-visible lesson data.

- [ ] **Step 4: Run tests and commit**

Run: `npm test -- src/screens/client/clientLessons.test.tsx && npm run build`

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/client design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover client lessons and homework"
```

### Task 3: Client subscription, payments and profile

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/client/ClientSubscriptionScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/client/ClientPaymentsScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/client/ClientProfileScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/client/AccountDeletionScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/client/clientAccount.test.tsx`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: scenario subscription, payment history, profile, auth methods and deletion request.
- Produces: `client.subscription`, `client.payments`, `client.profile`, `client.auth-methods`, `client.account-deletion`, `client.account-deletion-status`.

- [ ] **Step 1: Write failing state matrix tests**

```tsx
it.each(['active', 'none', 'debt', 'pending', 'overpayment', 'ended'])('shows subscription state %s', (variant) => {
  renderPrototype(`client.subscription.${variant}`, { role: 'client' })
  expect(screen.getByTestId(`subscription-${variant}`)).toBeInTheDocument()
})

it('allows cancellation only for a pending deletion request', async () => {
  const first = renderPrototype('client.account-deletion.pending', { role: 'client' })
  expect(screen.getByRole('button', { name: 'Отменить запрос' })).toBeEnabled()
  first.unmount()
  renderPrototype('client.account-deletion.processing', { role: 'client' })
  expect(screen.queryByRole('button', { name: 'Отменить запрос' })).not.toBeInTheDocument()
})
```

- [ ] **Step 2: Run the account tests to prove they fail**

Run: `npm test -- src/screens/client/clientAccount.test.tsx`

Expected: FAIL because the account surfaces are absent.

- [ ] **Step 3: Implement account surfaces without staff actions**

The subscription screen must not add renewal or purchase actions that are not
present in the client app. Profile includes personal data, login methods,
legal documents and account deletion routes.

- [ ] **Step 4: Run tests, build and commit**

Run: `npm test -- src/screens/client && npm run build`

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/client design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover client account surfaces"
```

### Task 4: Teacher schedule and assigned students

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/teacher/TeacherScheduleScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/teacher/TeacherStudentsScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/teacher/TeacherStudentCard.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/teacher/TeacherStatsScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/teacher/teacherPortal.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/teacher/teacher.css`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: assigned lessons, assigned students, homework and teacher report scenario data.
- Produces: `teacher.schedule`, `teacher.students`, `teacher.student-card`, `teacher.lesson-details`, `teacher.homework-editor`, `teacher.stats`.

- [ ] **Step 1: Write failing RBAC and navigation tests**

```tsx
it('shows only assigned teacher navigation', () => {
  renderPrototype('teacher.schedule', { role: 'teacher' })
  expect(screen.getByRole('button', { name: 'Чат' })).toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'Расписание' })).toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'Ученики' })).toBeInTheDocument()
  expect(screen.queryByText('Абонементы')).not.toBeInTheDocument()
  expect(screen.queryByText('Контакты')).not.toBeInTheDocument()
})
```

- [ ] **Step 2: Run the teacher tests to prove they fail**

Run: `npm test -- src/screens/teacher/teacherPortal.test.tsx`

Expected: FAIL because teacher surfaces are not registered.

- [ ] **Step 3: Implement assigned-only teacher surfaces**

Teacher Student Card must expose only permitted overview, lessons, progress and
shared homework/comment data. Add distinct readonly, forbidden, empty and error
routes. No lesson creation or commerce controls may render.

- [ ] **Step 4: Run the role portal gate**

Run: `npm test -- src/screens/auth src/screens/client src/screens/teacher && npm run build`

Expected: all role portal tests PASS and build exits 0.

- [ ] **Step 5: Commit the role portal milestone**

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/teacher design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover teacher workspace surfaces"
```
