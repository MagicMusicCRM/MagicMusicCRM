# P7 — Regression Evidence & Acceptance Ledger (KVA-202)

Living evidence for **P7-3** (pre-merge regression checklist green across all phases)
and the reference for **P7-4** (owner per-window acceptance). Tracks the v7
Redesign→Prod migration (KVA-192). Branch stack:
`p0(kva-193) → p1(kva-194) → p2(kva-195) → p3(kva-196)`; the new-backend + UI-wiring
work (P5/P5b/P5c/P4) rides on the P3 branch.

## §5f pre-merge checklist — standing gates

Every frontend phase commit was verified against:

| Gate | How | Status |
|---|---|---|
| `flutter analyze` clean | full-tree analyze | ✅ green at each stable point |
| `flutter test` green | full suite | ✅ **164/164** at last full run |
| `git diff server/` empty on reskin phases | staged-name check | ✅ enforced per commit |
| `lib/core/services/*` request/response unchanged on reskins | grep locked calls | ✅ (services only **added** to, for new endpoints) |
| backend `tsc --noEmit` + `jest` | server suite | ✅ **316/316** (37 suites) |
| RBAC contract preserved | grep gating | ✅ A1 manager+system_admin gate survived the P5-3 restyle |

## Phase status

### Done & committed (verified headless)
- **P0** — design tokens + v7 component layer (`design_tokens.dart`, `widgets/v7/*`).
- **P1** — per-role nav + RBAC (`crm_nav_rbac`, admin = Чат/Расписание/Клиенты),
  auth screens, splash. _(P1-7 network baseline — see blocked.)_
- **P2** — create-lesson conflicts (P2-4), attendance sheet (P2-5), schedule detail
  sheet + token restyle (P2-6). _(P2-1/2/7/8 — see blocked.)_
- **P3** — lead card v7 tabs (P3-1/P3-6), convert-lead sheet (P3-2),
  family member add/remove (P3-9, `3cff5921`). _(P3-3/5/7/8 — see remaining.)_
- **P5-5** — expense write API `/crm/expenses` CRUD + audit + tests (`2b423bfe`).
- **P5b** — subscription packages: migration `0033`, CRUD, atomic issue,
  idempotent `lessons_used` decrement on attendance (`416da6a8`).
- **P5c** — homework backend: migration `0034`, `homework_attachment` file purpose,
  `/crm/homeworks` + RBAC (`9941443b`).
- **P5-6 / P5b-5 / P5c-4 / P5c-5** — expense sheet, subscription catalog + issue,
  «Задать ДЗ», client homework UI (`fbbb02b7`, `eb7b3810`).
- **P5-1 / P5-2 / P5-3 / P5-4** — reports, tasks, users, settings v7 restyles
  (`eb7b3810`, `bba643d2`).
- **P4-7 / P4-1 (partial)** — notification center + chat-chrome v7 restyle (`bba643d2`).
- **P5-7 (partial)** — phone-review + lead-merge data-quality panel (`4484d8ec` + panel).
- **P7-2 (test artifact)** — the 5-role RBAC matrix test exists and passes
  (built in P1-2). The remaining P7-2 work is the owner's live walkthrough.

### Remaining — implementable (next headless passes)
- **P5-7 (rest)** — CSV/XLSX finance export buttons (`/analytics/finance/monthly.csv|.xlsx`),
  sources/data-quality/responsible analytics cards, account-deletion-request queue
  (`legal` controller). Backends exist; needs service methods + UI.
- **P3-3** slide-out filter drawer, **P3-5** dual-target column editor,
  **P3-8** deep-link + state preservation — restructures, not reskins.
- **P4-2** message ⋯ menu parity audit.

### Blocked — needs the owner's runtime/device (NOT headless-completable)
These are not deferrable by writing more code; they require a real device, a live
seeded backend, or production data, and running them blind would be unsafe.

| Item | Why blocked | Owner action |
|---|---|---|
| **P6-1..5** (KVA-201) data cleanup | Operates on **real production data** (199 room overlaps, fake emails, phone normalization, lesson-split, missing comments). Writing/running destructive migrations blind is unsafe. | Run the §4 Phase-6 SQL with `import_batches` dry-run → apply, against staging then prod. |
| **P1-7** network baseline | Needs a live **seeded backend** to capture request/response baselines. | Run the baseline capture against staging. |
| **P2-1** sticky-scroll header, **P2-2** block-drag, **P2-7** teacher schedule | Gesture/visual behaviour only verifiable **on device**. | On-device iteration. |
| **P2-8** lesson-split rows | Blocked on **P6-4** (data fix) landing first. | After P6-4. |
| **P4-3** voice (E2), **P4-4** gallery (E3) | "Verify/repair" — confirming the fix needs **audio playback / image pick** on device. | On-device repro + verify. |
| **P7-1** Windows on-device re-audit | Requires the **Windows build on a device**. | Owner runs the shipped reskin. |
| **P7-4** per-window owner acceptance | Owner sign-off vs the v7 prototype. | Owner review using this ledger. |

## Verification commands (re-runnable)
```
flutter analyze                       # → No issues found!
flutter test                          # → 164/164
cd server && npx tsc --noEmit         # → exit 0
cd server && npx jest --runInBand     # → 316/316 (37 suites)
git diff --name-only -- server/       # empty on frontend-only commits
```
