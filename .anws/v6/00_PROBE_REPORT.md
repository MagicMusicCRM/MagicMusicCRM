# 🔎 MagicMusicCRM v6 — Probe & UX Claim-Gap Report

| Поле | Значение |
|---|---|
| Дата | 2026-08-04 |
| Режим | Deep Probe + Product UX audit |
| Основание | Текущее приложение, v4 evidence/inventory, ТЗ владельца и 4 референсных скриншота HolliHop |
| Вывод | **v4 нельзя считать выполненным на 100%; product acceptance не пройдена** |

---

## 1. Executive conclusion

Техническая работа v4 значительна: реализованы access-control, integrity, schedule constraints, commerce snapshots, client-card tabs и отдельные компоненты desktop workspace. Но утверждение «правки выполнены на 100%» не подтверждается самим репозиторием.

Главная причина расхождения — проверялись изолированные классы, contracts и widget harness, а не production route × real account × Windows mouse workflow. В результате часть функций существует в коде, но пользователь её не видит; часть реализована в другом месте или в урезанном виде; часть оставлена рядом с legacy-сценарием.

### Verdict

| Класс | Итог |
|---|---:|
| Реализовано и подключено | Часть backend/integrity и отдельных UI-сценариев |
| Реализовано частично | Карточка клиента, оплаты, расписание клиента, deep links, задачи, аналитика |
| Реализовано, но не подключено | Desktop workspace tabs/persistence/logout coordination |
| Не реализовано системно | Persistent desktop scrollbars/mouse UX, full workflow acceptance, единая configurable CRM |
| Release | **NOT APPROVED** до закрытия High/security/UAT и v6 acceptance |

---

## 2. Evidence that v4 is not 100% complete

### P0 — Desktop workspace is dead infrastructure

- `AccountWorkspaceStore`, `WorkspacePersistenceBinding`, `WorkspaceLogoutCoordinator` and `DesktopWorkspaceShell` exist under `lib/core/workspace/`.
- Production search outside that directory returns **zero imports/usages** of the shell, persistence binding, logout coordinator and workspace entity-link button.
- `lib/main.dart` mounts `MaterialApp.router` directly and does not wrap routed role surfaces in the workspace shell.
- `docs/audits/v4-current-state-inventory.json` still contains **327** entries with `status = workspace-migration-pending`.

**Impact:** tests can prove the isolated controller/store, but no account receives persistent tabs in the actual application. This exactly explains why the owner cannot see the feature.

### P0 — Desktop scrolling is not system-wide

- Global `NoGlowScrollBehavior` only removes the overscroll indicator.
- Across 259 Flutter source files, explicit `Scrollbar` usage was found in only four call sites; only two set `thumbVisibility: true`.
- No app-wide `ScrollbarThemeData`, `trackVisibility`, desktop axis policy or scrollable inventory exists.

**Impact:** mouse users depend on wheel/trackpad behavior and cannot reliably grab a visible vertical or horizontal thumb.

### P0 — Client card layout and schedule placement diverge from the specification

- Desktop `ClientCard` is a centered dialog capped at **600 px** and 85% height, not a full-screen/large desktop workspace.
- `StudentScheduleSection` is rendered inside the Info tab.
- The Lessons tab is explicitly a **flat upcoming/past list** and routes out to the global schedule.
- No embedded client Month/Week/Day calendar with selected-client green and other lessons gray was found.

**Impact:** individual pieces exist, but the standard desktop workflow still requires context switching and does not match the supplied HolliHop reference.

### P0 — Payments exist but the add-payment workflow is incomplete

- Student card already has a separate `Оплаты` tab and personal-account ledger.
- `TopUpDialog` accepts only amount and comment; it hardcodes current date and `method: other`.
- Branch, payment method selector, payment status, accepted-by employee/date and invoice are not part of create flow.
- Discount and installments exist in subscription issue contracts, not as one coherent direct-payment/client-account UX; surcharge is not surfaced in the form.

**Impact:** this is not the requested operational cashier flow shown in the reference screenshot.

### P0 — Deep linking is infrastructure-first, adoption-second

- Typed `EntityLink`/registry/navigator already exist and should be reused.
- Lesson detail receives display names instead of typed entity IDs, so Student/Lead, Teacher and Room remain text.
- Client Lessons can jump to schedule, but that is one directional special-case, not system-wide connected navigation.

**Impact:** “связанная запись везде кликабельна и Back возвращает контекст” is not yet a product invariant.

### P1 — Parallel product paths remain

- `TasksWidget` and `SharedTasksV4Panel` remain neighboring experiences.
- Shared Tasks itself has both a header add button and a FAB.
- `ReportsWidget` still exposes separate Reports, Finance and Summary tabs with distinct loaders.

**Impact:** v4 improved components without completing canonical cutover.

---

## 3. UX audit by core workflow

| Workflow | Current implementation | Gap | Priority |
|---|---|---|---:|
| Open 2–10 records in desktop tabs | Isolated workspace classes/tests | Not mounted; no real restart/logout proof | P0 |
| Work only with a mouse | A few local scrollbars | No visible draggable bars on most scrollables/axes | P0 |
| Find/create Student | Board exists; create form elsewhere | Main Students has no canonical create action; stages hardcoded | P0 |
| Open client and work quickly | 600 px modal with horizontal tab strip | Not full-screen/large desktop; high context density in Info | P0 |
| Set preferred schedule | Recurring series editor exists in Info | Wrong information architecture; no dedicated Lessons/calendar workspace | P0 |
| Inspect client lessons | Flat past/upcoming list | No Month/Week/Day, branch default, own-green/others-gray context | P0 |
| Add client payment | Ledger and minimal top-up | Missing operational payment attributes and commercial controls | P0 |
| Follow related records | Partial typed navigation infrastructure | Lesson and many entity refs not clickable; context restoration inconsistent | P0 |
| Create/close shared task | Legacy + shared task panels | Duplicate create actions and two mental models | P0 |
| Review business state | Multiple reporting tabs | No single filter contract/dashboard/drilldown parity | P1 |
| Recover from errors | Implemented inconsistently per screen | No route-wide loading/empty/error/forbidden/retry acceptance | P1 |

---

## 4. Mapping of the supplied 26-point specification

Statuses are based on source/evidence. `Runtime UAT` means the code may exist, but the real-account/device workflow was not proven.

| № | Requirement | Status | Required v6 action |
|---:|---|---|---|
| 1 | 2–10 persistent PC tabs; clear on logout | **Not connected** | Mount existing workspace at production shell; account-scoped restore/logout/device gate |
| 2 | Required Lead name/phone/source | Partial / runtime UAT | Effective field schema + backend/UI parity |
| 3 | Source only from dictionary | Partial | Move to published dictionary; no free-text fallback |
| 4 | Notify only for inbound lead | Backend evidence exists / runtime UAT | Real-account notification acceptance |
| 5 | Director manages sources/fields; safe archive | Partial | Unified config lifecycle, usage impact and archive rules |
| 6 | Horizontal client-card tabs | Exists | Add desktop overflow/scrollbar/keyboard acceptance |
| 7 | Director manages subscription catalog | Exists partially | Canonical settings location + role/device UAT |
| 8 | Change assigned package for allowed staff | Commerce replacement exists | Confirm all allowed roles and client-card affordance |
| 9 | Discount | Subscription contract exists | Expose coherent client commercial/payment UX |
| 10 | Installments and cash/non-cash | Subscription contract exists | Expose in canonical forms; define direct-payment semantics |
| 11 | Required Student fields | Partial | Effective school/branch metadata and backend parity |
| 12 | Clear “Create schedule” action | Partial | Move/create in canonical Lessons tab |
| 13 | Clear global schedule creation | Partial | Typed ClientRef selector and unambiguous labels |
| 14 | Schedule → client; client weekly calendar | **Partial/missing** | System-wide links + embedded Month/Week/Day client calendar |
| 15 | Back returns to prior schedule context | Partial | One route-stack/context preservation contract |
| 16 | Required room/teacher/hours constraints | Backend largely exists | UI explanation + seeded device acceptance |
| 17 | Teacher availability and branch assignment | Backend largely exists | Canonical UI and branch-aware UAT |
| 18 | Student/teacher/room/branch conflicts | Backend largely exists | Matrix UX and concurrency acceptance |
| 19 | Valid Excel export | Unverified | File-open contract and real exported artifact gate |
| 20 | Student status counts; Director access control | Partial | Configurable funnel + delegated capability matrix |
| 21 | Remaining active-subscription lessons | Partial | Canonical client summary + mouse horizontal-scroll acceptance |
| 22 | Client tasks, all-day/interval/reminder/audience | Partial | One shared-task UX with branch/all-school scope |
| 23 | Close task in client tab | Exists partially | Canonical close lifecycle + runtime UAT |
| 24 | Teacher calendar Day/Week | Read-only Day/Week exists | Validate requested interaction vs protected teacher permissions |
| 25 | Director-only client deletion + linked-impact warning | Archive/preview exists | Confirm role matrix and payment/conversion preservation |
| 26 | Lesson auto-completes after time | Worker exists | Production worker/retry/poison readiness acceptance |

---

## 5. HolliHop benchmark: what to adopt, not clone

The reference is useful for information architecture: client context, preferred schedule, calendar, personal account and history are adjacent and operational actions are explicit. The official HolliHop materials also describe a calendar with rooms/teachers, client preferences/history, tasks/reminders and financial operations.

Adopt:

- client-centric navigation and one-screen operational context;
- explicit labels and visible table/scroll affordances;
- preferred schedule separated from generic profile information;
- personal-account ledger plus a complete add-payment form;
- linked entities as navigation, not inert text.

Do not adopt blindly:

- visual style inconsistent with the approved MagicMusic v7 tokens;
- role behavior that conflicts with MagicMusic capability/resource-scope rules;
- mutable financial history or unsafe deletes;
- one-school assumptions where MagicMusic requires school default + branch override.

---

## 6. Runtime inspection limitation

The existing Windows Release executable was detected and its window was targeted. Windows Graphics Capture failed with `0x80004002 (interface not supported)` for this Flutter window, so no trustworthy live screenshots or mouse interactions could be captured in this probe. Authentication was not automated and no account data was mutated.

Therefore this report is a deep source/evidence audit plus inspection of the supplied DOCX/screenshots, **not** final real-account UAT. Final acceptance must still run on the seeded Windows build and Android device with role/branch accounts.

---

## 7. Recommended delivery order

1. Mount/reuse desktop workspace and prove account persistence/logout.
2. Add one global desktop scrollbar/mouse policy, then inventory exceptions.
3. Recompose client card for desktop: full/large workspace, canonical tabs and preserved context.
4. Move preferred schedule into Lessons and add client Month/Week/Day calendar with branch default and own/other visual hierarchy.
5. Complete Payments tab by reusing existing ledger/commerce APIs; add only missing server contract fields that are product-authoritative.
6. Enforce typed entity links in shared display components and lesson details.
7. Complete Students/Tasks/Reporting canonical cutovers.
8. Run route × role × branch × school × device workflow audit, then security/release gate.

---

## 8. Probe decision

**The v4 claim is rejected as a product-completion claim.** It is valid only as evidence that many underlying domain and integrity components were implemented. v6 must define completion by production mounting, visible workflow behavior and real-account UAT—not by isolated class/test existence.
