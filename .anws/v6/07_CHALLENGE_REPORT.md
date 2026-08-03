# Challenge Report — v6 UX/UI & Configurable CRM

> **Date:** 2026-08-04  
> **Scope:** approved PRD, architecture overview, ADR-001..006 and App Experience Redesign  
> **Verdict:** **YELLOW-GREEN** — no Critical blockers; High risks are converted into mandatory design constraints and tasks.

## 1. Review method

The proposal was challenged from architecture, security/privacy, Flutter platform behavior, accessibility, operations and delivery perspectives. The review asks where an apparently polished redesign could still reproduce the v4 claim-gap: code exists, but production behavior is incomplete or unsafe.

## 2. Findings

### CH-01 — Two navigation truths can diverge

- **Severity:** High
- **Failure mode:** GoRouter URL, `WorkspaceController` tab stack and breadcrumb metadata evolve independently. Direct links show the right screen but wrong path/history, or restored tabs navigate through stale routes.
- **Mitigation adopted:** ADR-003 requires one canonical location descriptor and an adapter over existing router/workspace/entity metadata. A second registry is forbidden. Restoration validates route schema, access and resource state.
- **Mandatory evidence:** direct-link → breadcrumb reconstruction; per-tab Back/Forward; restart/logout; stale/forbidden route tests.

### CH-02 — Modal-to-route migration can duplicate business calls

- **Severity:** High
- **Failure mode:** A new routed screen copies an existing modal form/provider and performs duplicate fetches or mutations, violating the zero-backend-regression principle.
- **Mitigation adopted:** Reuse the existing content/controller/service path inside adaptive containers; keep wire-to-service baseline/diff per migrated screen. Frontend phases assert empty `server/` diff.
- **Mandatory evidence:** before/after API trace and exactly-one mutation under retry/double-click.

### CH-03 — Android predictive Back can bypass dirty-state handling

- **Severity:** High
- **Failure mode:** UI Back prompts, but Android system gesture or sheet dismissal loses input because pop eligibility is not known ahead of time.
- **Mitigation adopted:** One ahead-of-time pop policy using `PopScope`/`NavigatorPopHandler`/`Form.canPop`; overlay, route, breadcrumb and tab-close exits share Save/Discard/Cancel.
- **Mandatory evidence:** hardware/predictive Back matrix for clean/dirty forms, partial/full sheet and nested dialog.

### CH-04 — Capability-hidden UI can still leak through preload

- **Severity:** High
- **Failure mode:** A Manager never sees Finance, but a dashboard provider still requests school-finance endpoints; a Teacher route briefly fetches a full client before projecting fields.
- **Mitigation adopted:** Resolve capability/resource projection before navigation and data fetch. Unsupported sections are not built and not requested. Server remains authoritative.
- **Mandatory evidence:** negative network assertions for Teacher/Admin/Manager, actor matrix and payload leak scan.

### CH-05 — A global scrollbar wrapper can break nested scrolling

- **Severity:** High
- **Failure mode:** The apparent one-line fix attaches one controller to several positions, produces `attached to multiple scroll views`, traps the wheel or displays unusable bars.
- **Mitigation adopted:** ADR-004 separates global styling from explicit scroll-surface ownership; each axis owns one controller and nested behaviors are inventoried.
- **Mandatory evidence:** mouse-only traversal for every inventory row plus pointer/controller exception log gate.

### CH-06 — Client calendar can become a privacy/performance backdoor

- **Severity:** Medium
- **Failure mode:** To show other lessons gray, the client card downloads an unbounded school schedule or data not visible to the actor.
- **Mitigation adopted:** Query only actor-visible lessons for visible date range and effective scope; selected client ID controls presentation only. Other events expose only already-authorized projection.
- **Mandatory evidence:** bounded viewport request, role/scope test, no hidden client fields in event payload.

### CH-07 — Tabs + breadcrumbs + page actions can overcrowd medium desktop

- **Severity:** Medium
- **Failure mode:** At 840–1000px the context bar truncates the current object and primary action, reducing rather than improving navigation.
- **Mitigation adopted:** Breadcrumb ellipsis retains root/nearest parent/current; secondary actions move to labelled overflow; medium widths use Back + title/path menu instead of desktop imitation.
- **Mandatory evidence:** golden/widget layouts at 600, 840, 1000 and 1200+ with long Russian names/text scale.

### CH-08 — Persisted workspace can restore unsafe or obsolete context

- **Severity:** Medium
- **Failure mode:** A role change, deleted entity or route schema update restores a forbidden tab or cached sensitive record.
- **Mitigation adopted:** Persist only safe location/view state, key by account and schema version, validate current access/resource, and clear current account cache on logout.
- **Mandatory evidence:** role downgrade, deleted/archived entity, schema bump, user-switch and logout tests.

### CH-09 — Role-oriented shells can reintroduce hard-coded RBAC

- **Severity:** Medium
- **Failure mode:** Separate role menus drift from set-based backend policies and confuse Admin/Manager hierarchy.
- **Mitigation adopted:** One capability-projected navigation model with role-specific ordering/density only. School finance is guarded by `CrmPolicy.canReadSchoolFinance`, not `isStaff`.
- **Mandatory evidence:** five-role navigation and endpoint matrix; no Admin managerial routes; no Manager school finance.

### CH-10 — A large design-system expansion would delay user-visible fixes

- **Severity:** Medium
- **Failure mode:** The team builds generic scaffolding before migrating screens, increasing abstractions without production benefit.
- **Mitigation adopted:** ADR-001 applies reuse-first/YAGNI. Add a primitive only for a confirmed repeated behavior; first production consumer and runnable check ship together.
- **Mandatory evidence:** each new primitive references at least two planned consumers or replaces an existing incomplete shared widget.

### CH-11 — Color hierarchy can conflict with lesson lifecycle

- **Severity:** Medium
- **Failure mode:** Green selected-client highlighting is mistaken for lesson success/completion; gray events appear disabled.
- **Mitigation adopted:** Client relation uses marker/label plus tint; lifecycle/reservation remains independent icon/text/token. Legend and screen-reader label state both dimensions.
- **Mandatory evidence:** color-blind/non-color check and lifecycle × selected-client state matrix.

### CH-12 — Real-account UAT can remain indefinitely “later”

- **Severity:** High
- **Failure mode:** Automated tests pass, but recipients, scopes, desktop input or auth-specific behavior are never tested on the owner's account, repeating v4.
- **Mitigation adopted:** Real-account UAT is a release dependency, not a post-release task. Missing account/device/backend evidence stays `blocked`; production cannot be marked approved.
- **Mandatory evidence:** signed 26-point matrix plus top workflows for all roles/scopes/devices.

## 3. Threat-oriented misuse cases

| Misuse | Required defense |
|---|---|
| User edits deep-link UUID/scope | Server resource-scope enforcement; actor-safe 404/403 state; no existence detail |
| Manager opens cached Director finance tab after role downgrade | Restoration access check before provider creation; remove tab and notify safely |
| User double-clicks payment save or retries after timeout | Stable idempotency metadata, disabled saving action, ledger reconciliation |
| User closes dirty form via OS Back/tab/logout | Unified dirty-state decision before pop/clear; logout may require explicit discard |
| Workspace cache inspected locally | Store route/view state only; no domain payloads/tokens; account partition and clear-on-logout |
| Teacher follows linked client entity | Typed actor-scoped projection only; forbidden fields never fetched/serialized |

## 4. Required corrections already applied to design

- Added canonical navigation-location contract and explicitly prohibited a second registry.
- Changed mobile primary workflows from modal-first to route-first; retained sheets only for contextual work.
- Added ahead-of-time system/predictive Back and one dirty-state exit policy.
- Changed scrollbar plan from blanket wrapper to explicit scroll ownership.
- Added prefetch-negative access tests and safe persisted-state rules.
- Split selected-client highlighting from lesson lifecycle semantics.
- Made real-account UAT and security evidence hard release dependencies.

## 5. Decision

Proceed to blueprint. No Critical finding remains. High findings CH-01..05 and CH-12 must appear as P0 tasks/acceptance gates. If implementation introduces a second navigation registry, duplicates service calls, preloads forbidden data or treats device UAT as optional, this verdict returns to **RED**.

