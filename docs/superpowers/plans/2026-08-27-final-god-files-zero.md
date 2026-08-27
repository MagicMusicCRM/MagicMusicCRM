# Final God Files 11→0 Master Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the three approved subplans, reduce every production god/brain owner to zero, and produce one exact global gate and review.

**Architecture:** Eleven owner cuts execute in four dependency-safe waves with lane smoke and independent commits. RepoWise and Sentrux measure every integrated lane; full executable and coverage gates run once after all owners integrate.

**Tech Stack:** Flutter/Dart/Riverpod, NestJS/TypeScript/PostgreSQL/Jest, RepoWise, Sentrux, Git

**Spec:** `docs/superpowers/specs/2026-08-27-final-god-files-zero-design.md`

## Global Constraints

- Implement the backend, Flutter CRM, and workspace/admin subplans without widening their frozen contracts.
- Preserve user changes and commit each lane separately; one integrator owns shared wiring.
- After every lane: focused smoke, exact RepoWise update/health/risk, Sentrux scan/health/rules.
- One full backend/Flutter/coverage gate after all eleven owners; no per-lane global suites.
- Completion means exact production `god_class 11 -> 0` and production `brain_method -> 0`, not merely smaller files.

---

### Task 1: Commit the approved program documents

**Files:**
- Create: `docs/superpowers/specs/2026-08-27-final-god-files-zero-design.md`
- Create: `docs/superpowers/plans/2026-08-27-final-god-backend.md`
- Create: `docs/superpowers/plans/2026-08-27-final-god-flutter-crm.md`
- Create: `docs/superpowers/plans/2026-08-27-final-god-workspace-admin.md`
- Create: `docs/superpowers/plans/2026-08-27-final-god-files-zero.md`

- [ ] **Step 1: Validate docs and baseline**

```powershell
git diff --check
repowise status --format json
git status --short
```

Expected: RepoWise index equals `8fa82cb3a0c66de31575679079f9db850e5e3cc9`; only five program documents are uncommitted.

- [ ] **Step 2: Commit**

```powershell
git add docs/superpowers/specs/2026-08-27-final-god-files-zero-design.md docs/superpowers/plans/2026-08-27-final-god-backend.md docs/superpowers/plans/2026-08-27-final-god-flutter-crm.md docs/superpowers/plans/2026-08-27-final-god-workspace-admin.md docs/superpowers/plans/2026-08-27-final-god-files-zero.md
git commit -m "docs(health): plan final god recovery"
```

### Task 2: Execute Wave 1 backend

**Files:** Exact ownership is in `2026-08-27-final-god-backend.md`.

- [ ] **Step 1:** Run Finance, StudentFunnel and LessonCommand lanes in parallel; lane agents do not edit `crm.module.ts`.
- [ ] **Step 2:** Review and integrate each lane commit, run its smoke, and reject any semantic widening.
- [ ] **Step 3:** Make the single provider/privacy wiring commit and run backend typecheck/build plus combined boundary smoke.
- [ ] **Step 4:** Reindex; require backend god owners `3 -> 0`; run Sentrux rescan/health/rules.

### Task 3: Execute Wave 2 Flutter form/finance owners

**Files:** Exact ownership is in `2026-08-27-final-god-flutter-crm.md`, Tasks 1–3.

- [ ] **Step 1:** Run PreferredSchedule, SharedTask and FinanceWidget lanes in parallel.
- [ ] **Step 2:** Review lifecycle tests, public APIs and view dependency direction; run combined smoke.
- [ ] **Step 3:** Reindex each accepted commit; require those three god/brain owners absent; run Sentrux after each.

### Task 4: Execute Wave 3 funnel/board/reference owners

**Files:** Exact ownership is in the Flutter CRM plan Tasks 4–5 and workspace/admin plan Task 1.

- [ ] **Step 1:** Run StudentFunnelEditor, StudentsBoard and ReferenceLifecycle lanes in parallel.
- [ ] **Step 2:** Integrate Funnel editor before StudentsBoard if provider contracts overlap; preserve optimistic/realtime precedence.
- [ ] **Step 3:** Run combined lane smoke, exact RepoWise health/recount and Sentrux after each accepted commit.

### Task 5: Execute Wave 4 ClientCard and ProductionWorkspace

**Files:** Exact ownership is in Flutter CRM Task 6 and workspace/admin Task 2.

- [ ] **Step 1:** Run ClientCard and ProductionWorkspace lanes in parallel with disjoint file ownership.
- [ ] **Step 2:** Integrate ClientCard first, then Workspace; run routed/dialog/entity-link/dirty-state combined smoke.
- [ ] **Step 3:** Reindex and require exact production `god_class 11 -> 0`, no brain methods, and all owner budgets green.

### Task 6: Run the single global executable and coverage gate

**Files:**
- Create: `.superpowers/final-god-zero/global-evidence.md`
- Create: `.superpowers/final-god-zero/change-risk.json`
- Create: `.superpowers/final-god-zero/pr-risk.json`

- [ ] **Step 1: Backend gate**

```powershell
cd server
npm test -- --runInBand --coverage
npm run typecheck
npm run build
cd ..
```

Expected: all suites/tests PASS, typecheck/build PASS, fresh ignored `server/coverage/lcov.info`.

- [ ] **Step 2: Flutter gate**

```powershell
flutter test --coverage
flutter analyze
```

Expected: all tests PASS, analyzer zero, fresh ignored `coverage/lcov.info`.

- [ ] **Step 3: Evidence metrics**

Hash both LCOV files, ingest coverage/test map, update exact RepoWise index,
run production god/brain recount, health for every original/new owner,
`get_change_risk`, PR `get_risk`, and verify hard/security arrays empty. Run
Sentrux rescan/health/rules and compare every root score to baseline.

### Task 7: Independent review, corrections and evidence commit

**Files:**
- Create: `.superpowers/final-god-zero/whole-review.md`
- Modify: the four program plan/spec Results sections

- [ ] **Step 1:** Give an independent reviewer the literal baseline..code-head range, frozen contracts, lane commits/smoke, global logs, LCOV hashes, RepoWise and Sentrux evidence.
- [ ] **Step 2:** Fix every Critical/Important finding in the owning lane and rerun focused smoke plus the single global gate.
- [ ] **Step 3:** Record Critical/Important/Minor totals and explicit rulings, append measured Results, run `git diff --check`, and commit only evidence/results.
- [ ] **Step 4:** Run `repowise update --index-only`; verify index equals evidence HEAD and worktree is clean.

Expected final state: production gods `0`, brains `0`, executable gates green, review Critical/Important `0/0`, exact indexed evidence HEAD, ready for pre-merge review.
