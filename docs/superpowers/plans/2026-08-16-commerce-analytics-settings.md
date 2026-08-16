# Commerce Analytics and Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Покрыть клиентскую коммерцию, школьную аналитику и все шесть областей системных настроек.

**Architecture:** Финансовые экраны используют локальные preview/result snapshots и не переписывают историю. Settings routes разделяются по шести production-областям, а вложенная CRM-конфигурация имеет собственный трёхпанельный workspace.

**Tech Stack:** React 19, TypeScript, Vitest, Testing Library, Recharts only where a production chart exists.

**Spec:** `docs/superpowers/specs/2026-08-16-full-ui-prototype-coverage-design.md`

## Global Constraints

- Сначала выполнить foundation, role portals и staff operations.
- Manager не видит school-finance, expenses и director-only mutations.
- Финансовые изменения показываются как append-only correction/reversal, а не редактирование истории.
- Поля финансирования занятия, оплаты преподавателю и списания остаются независимыми.
- Настройки сохраняют шесть production-областей и существующую вложенность.

---

### Task 1: Client commerce command surfaces

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/commerce/ClientBalanceScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/commerce/PaymentEditorSheet.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/commerce/PaymentCorrectionFlow.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/commerce/SubscriptionIssueFlow.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/commerce/SubscriptionReplaceFlow.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/commerce/SubscriptionCancelFlow.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/commerce/commerceFlows.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/commerce/commerce.css`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: client balance, payment, package, subscription and preview snapshots.
- Produces: balance, payment create/edit, correction/reversal, issue, replace and cancel surface ids with preview/result states.

- [ ] **Step 1: Write failing immutable-history tests**

```tsx
it('shows a superseding correction instead of editing the original payment', async () => {
  const { user } = renderPrototype('payment.correction.preview', { role: 'director' })
  await user.type(screen.getByLabelText('Причина'), 'Исправление ошибочной суммы')
  await user.click(screen.getByRole('button', { name: 'Подтвердить корректировку' }))
  expect(screen.getByText('Исходная операция сохранена в истории')).toBeInTheDocument()
  expect(screen.getByTestId('correction-result')).toBeInTheDocument()
})

it('keeps the issue draft after a stale version response', async () => {
  renderPrototype('subscription.issue', { role: 'director', state: 'stale' })
  expect(screen.getByLabelText('Абонемент')).toHaveValue('Развитие')
  expect(screen.getByRole('button', { name: 'Пересчитать' })).toBeInTheDocument()
})
```

- [ ] **Step 2: Run tests to prove they fail**

Run: `npm test -- src/screens/commerce/commerceFlows.test.tsx`

Expected: FAIL because commerce command surfaces do not exist.

- [ ] **Step 3: Implement payments and subscriptions**

Cover cash/non-cash payment, paid/pending/unpaid, assigned payment edit,
technical void, monetary reversal, correction, subscription issue and edit with
recalculation, own/other payer, installment, replacement, cancellation and refund.
Every mutation has preview, confirm, success, stale and safe error surfaces.

- [ ] **Step 4: Run tests, build and commit**

Run: `npm test -- src/screens/commerce && npm run build`

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/commerce design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover client commerce workflows"
```

### Task 2: Analytics, journals, expenses and teacher finance

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/analytics/AnalyticsScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/analytics/ReportOverview.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/analytics/JournalsScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/analytics/ExpensesScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/analytics/TeacherFinanceScreen.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/analytics/ExportResultDialog.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/analytics/analytics.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/analytics/analytics.css`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: one normalized period/branch filter and analytics scenario projections.
- Produces: overview, journal, expenses, teacher finance, XLSX/CSV result routes.

- [ ] **Step 1: Write failing filter and RBAC tests**

```tsx
it('applies one period and branch to every report section', async () => {
  const { user } = renderPrototype('analytics.overview', { role: 'director' })
  await user.selectOptions(screen.getByLabelText('Филиал'), 'Садовая')
  await user.click(screen.getByRole('button', { name: 'Месяц' }))
  for (const node of screen.getAllByTestId('report-scope')) {
    expect(node).toHaveAttribute('data-scope', 'month:branch-garden')
  }
})

it('does not mount finance requests for manager', () => {
  renderPrototype('analytics.overview', { role: 'manager' })
  expect(screen.queryByRole('button', { name: 'Финансы XLSX' })).not.toBeInTheDocument()
  expect(screen.queryByText('Расходы школы')).not.toBeInTheDocument()
})
```

- [ ] **Step 2: Run tests to prove they fail**

Run: `npm test -- src/screens/analytics/analytics.test.tsx`

Expected: FAIL because analytics is not a complete route family.

- [ ] **Step 3: Implement overview, journals and finance**

Keep top tabs `Обзор` and `Журналы`, common filter bar, existing vertical report
sections and journal dropdown. Add Director/system_admin expenses create/edit/delete
confirmation, teacher rates, accrual, payout and existing report states.

- [ ] **Step 4: Implement export result states**

Register `analytics.export.preparing`, `analytics.export.saved`,
`analytics.export.opened` and `analytics.export.invalid-format`. Do not generate
real files in the prototype; display the exact production-facing outcomes.

- [ ] **Step 5: Run tests, build and commit**

Run: `npm test -- src/screens/analytics && npm run build`

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/analytics design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover analytics and school finance surfaces"
```

### Task 3: Organization, schedule and sales settings

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/settings/SettingsShell.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/settings/OrganizationSettings.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/settings/ScheduleSettings.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/settings/SalesSettings.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/settings/LifecycleDialog.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/settings/settingsCore.test.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/settings/settings.css`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: settings role capabilities, organization, schedule references and package catalog.
- Produces: six-area shell plus organization, schedule and sales route families.

- [ ] **Step 1: Write failing area and compact-layout tests**

```tsx
it('keeps exactly six settings areas', () => {
  renderPrototype('settings.organization', { role: 'director', viewport: 'desktop' })
  expect(screen.getAllByTestId('settings-area')).toHaveLength(6)
})

it('uses the Раздел настроек select in compact mode', () => {
  renderPrototype('settings.schedule.hours', { role: 'director', viewport: 'compact' })
  expect(screen.getByLabelText('Раздел настроек')).toHaveValue('Расписание')
  expect(screen.queryByTestId('settings-left-rail')).not.toBeInTheDocument()
})
```

- [ ] **Step 2: Run tests to prove they fail**

Run: `npm test -- src/screens/settings/settingsCore.test.tsx`

Expected: FAIL because the settings shell is not modular.

- [ ] **Step 3: Implement organization and lifecycle surfaces**

Cover branches, reference catalogs, branch form and hours, rooms, disciplines,
loss reasons, preview/blockers/commit/archive/restore for supported entities.

- [ ] **Step 4: Implement schedule and sales settings**

Cover branch hours, teacher schedules, groups, group members/plan/lifecycle,
package list, create, edit, archive and restore. Readonly Manager actions are
absent or disabled exactly as in production.

- [ ] **Step 5: Run tests, build and commit**

Run: `npm test -- src/screens/settings/settingsCore.test.tsx && npm run build`

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/settings design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover organization schedule and sales settings"
```

### Task 4: CRM configuration, users, access and data maintenance

**Files:**
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/settings/CrmConfigurationWorkspace.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/settings/UsersSettings.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/settings/PersonEditor.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/settings/AccessEditor.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/settings/DataMaintenanceSettings.tsx`
- Create: `design_prototypes/magicmusic-light-design-lab/src/screens/settings/settingsAdvanced.test.tsx`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts`
- Modify: `design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx`

**Interfaces:**
- Consumes: CRM configuration draft/version, people/access records, phone queue and deletion requests.
- Produces: all CRM, Users and Data settings surfaces, previews and result states.

- [ ] **Step 1: Write failing configuration and secret-access tests**

```tsx
it('renders the six CRM configuration areas and editor pane', () => {
  renderPrototype('settings.crm.fields', { role: 'director', viewport: 'desktop' })
  expect(screen.getAllByTestId('crm-config-area')).toHaveLength(6)
  expect(screen.getByText('Выберите элемент для просмотра и настройки')).toBeInTheDocument()
})

it('shows managed email and password only to director and system administrator', () => {
  const first = renderPrototype('settings.users.access', { role: 'director' })
  expect(screen.getByRole('button', { name: 'Показать пароль' })).toBeInTheDocument()
  first.unmount()
  renderPrototype('settings.users.access', { role: 'manager' })
  expect(screen.queryByRole('button', { name: 'Показать пароль' })).not.toBeInTheDocument()
})
```

- [ ] **Step 2: Run tests to prove they fail**

Run: `npm test -- src/screens/settings/settingsAdvanced.test.tsx`

Expected: FAIL because advanced settings are incomplete.

- [ ] **Step 3: Implement CRM draft, preview, publish and history**

Create three desktop panes and compact horizontal area selector for fields and
categories, field options, business parameters, funnels, lessons and payment,
and immutable version history. Cover school scope, branch override, draft,
preview, publish, realtime result and rollback.

- [ ] **Step 4: Implement people, access and lifecycle**

Cover Access, Staff, Teachers; create/edit; at least one branch; multiple branches;
teacher schedule/rate; initial and later roles; provision access; current email;
audited managed password reveal; offboarding and restore. system_admin cannot be
created through the ordinary person form.

- [ ] **Step 5: Implement data maintenance**

Cover data quality, phone queue fix/accept with reason, Lead merge, deletion
requests and pending/processing/completed/rejected transitions with role-correct
actions.

- [ ] **Step 6: Run the commerce/settings gate**

Run: `npm test -- src/screens/commerce src/screens/analytics src/screens/settings && npm run build`

Expected: all tests PASS and build exits 0.

- [ ] **Step 7: Commit the milestone**

```bash
git add design_prototypes/magicmusic-light-design-lab/src/screens/settings design_prototypes/magicmusic-light-design-lab/src/catalog/screenManifest.ts design_prototypes/magicmusic-light-design-lab/src/AppRouter.tsx
git commit -m "feat: cover CRM access and maintenance settings"
```
