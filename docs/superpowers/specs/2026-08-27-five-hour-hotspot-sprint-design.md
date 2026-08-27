# Five-Hour Hotspot Sprint Design

**Status:** owner-approved in chat; written-spec review pending

**Baseline:** `bc7dce8aa234c0d1861e0ba6313274d6448b60b2` (short form `bc7dce8a`)

**Execution budget:** 300 minutes of wall-clock time from implementation start

## Goal

Complete three independent, bounded architecture cuts in one five-hour
execution window:

1. make payment-form idempotency identity follow the edited payload;
2. turn the preview-token file into a stable facade over domain modules;
3. move lesson-details projection out of the schedule widget into a pure,
   testable presenter.

The sprint improves production candidates 3, 6 and 7 from the exact RepoWise
`weighted_deficit` ranking at the baseline. Candidates 1 and 4 were analyzed
but are frozen for this sprint because their safe cuts exceed the timebox.

## Baseline and Rationale

| Rank | File | Health | Deficit | Primary signal |
|---:|---|---:|---:|---|
| 1 | `lib/features/crm/presentation/client_forms/client_create_dialogs.dart` | 1.23 | 7,210 | nested complexity |
| 3 | `lib/features/crm/presentation/client_card/client_payment_form.dart` | 2.84 | 6,435 | untested hotspot |
| 4 | `lib/features/crm/presentation/client_card/client_card_student.dart` | 1.90 | 6,350 | co-change scatter |
| 6 | `server/src/crm/commerce/subscription-preview-token.ts` | 1.14 | 6,229 | co-change scatter |
| 7 | `lib/features/admin/presentation/widgets/schedule_widget_actions.dart` | 2.35 | 6,226 | nested complexity |

RepoWise found no file-specific governing decision for the three selected
owners. Git archaeology shows they are feature-active and recently changed.
This design therefore follows `docs/architecture/CURRENT-DECISIONS.md` and the
repository `AGENTS.md` as the governing rules.

The deterministic RepoWise split suggestions for the payment and token files
are `XL` with medium confidence and predict no direct score recovery. This
design does not apply those mechanical suggestions. Each cut instead follows a
named behavior or domain boundary with characterization tests.

## Frozen Global Contracts

- Production remains one `Flutter -> NestJS -> PostgreSQL` runtime.
- Flutter continues to use existing services/providers; widgets gain no direct
  database or Supabase access.
- Backend RBAC and resource-scope checks remain authoritative.
- Money and lesson commands retain transaction, expected version,
  idempotency, audit/outbox and append-only facts.
- Existing HTTP routes, DTO/JSON shapes, database schema, migrations,
  provider APIs and public Flutter constructors remain unchanged.
- Russian UI copy, widget keys, navigation behavior and the Deep Charcoal &
  Sophisticated Gold theme remain unchanged.
- No production mutation, deployment, data cleanup or history rewrite is in
  scope.

## Architecture

### Lane A: Flutter Payment Mutation Session

#### Problem

`ClientPaymentForm` and `ClientPaymentAdjustmentForm` already preserve a
`MagicMutationIdentity` for an unchanged retry and rotate it after the user
edits an attempted draft. The transition, payment-reversal and
adjustment-reversal forms create one final identity for their entire widget
lifetime. After a failed request, the user can edit the payload and submit the
changed command under the old idempotency key.

The required invariant is:

```text
same logical payload retry -> same requestId/idempotencyKey
payload edited after an attempt -> new requestId/idempotencyKey
```

#### Design

Add one private `_PaymentMutationSession` inside
`client_payment_form.dart`. It owns the current `MagicMutationIdentity` and
whether that identity has been attempted.

- `identityForAttempt()` marks the current identity as attempted and returns
  it.
- `hasAttempted` exposes that state for the existing retry button labels.
- `payloadChanged()` rotates the identity only when the current identity has
  already been attempted.
- Rotation never occurs on build, validation, focus, error rendering, an
  unchanged retry or a server response alone.
- Every user handler that changes a submitted field calls `payloadChanged()`.
- Fields remain disabled while their existing `_busy` flag is true.

Use the session in these five form owners:

- `ClientPaymentForm`;
- `_ClientPaymentTransitionForm`;
- `_ClientPaymentReversalForm`;
- `_ClientAccountAdjustmentReversalForm`;
- `ClientPaymentAdjustmentForm`.

The data flow remains:

```text
payment form
  -> typed submission + MagicMutationIdentity
  -> client_card_student callback
  -> MagicCrmService
  -> postIdempotent backend request
```

`client_card_student.dart`, `MagicCrmService`, backend endpoints, input DTOs,
preview tokens and `expectedVersion` handling do not change.

#### Error Handling

A failed submission keeps its identity so the exact payload can be retried.
The existing localized error remains visible until the user edits a payload
field or retries. Editing after an attempt clears the existing form error and
rotates the identity exactly once for the new draft generation.

#### Tests

Modify:

- `test/features/commerce/client_payment_form_test.dart`;
- `test/features/commerce/client_payments_tab_test.dart`.

Characterization must prove for every form owner:

- an unchanged retry reuses both `requestId` and `idempotencyKey`;
- changing every command-relevant field after an attempt rotates both values;
- ordinary rebuilds do not rotate either value;
- `expectedVersion`, preview token, endpoint selection and typed callback
  payload remain unchanged.

Do not change `_popPaymentSheet`; it contains a recent Android stabilization.

### Lane B: Backend Preview-Token Facade

#### Problem

`subscription-preview-token.ts` combines eight payload contracts, eight HMAC
domains, sixteen sign/verify functions, the shared token codec, primitive
validators and eight compound validators. The file has high coverage but no
direct golden contract suite. Its primary risk is accidental cross-domain or
wire-format drift during future changes.

#### Design

Keep `subscription-preview-token.ts` as the canonical public facade and old
import path. Move existing behavior into four responsibility-named modules:

```text
subscription-preview-token.ts                 public facade
  -> subscription-preview-token-subscription.ts  purchase/replace/cancel
  -> subscription-preview-token-payment.ts       reversal/correction/adjustment
  -> subscription-preview-token-schedule.ts      lesson transition/plan end
       -> subscription-preview-token-core.ts      codec, HMAC, error, primitives
```

The dependency direction is `facade -> domain modules -> core`. Domain modules
must not import the facade or one another. The core module owns the only
`SubscriptionPreviewTokenError` class; the facade re-exports that exact class
so all existing `instanceof` checks retain identity.

All current production consumers continue importing
`subscription-preview-token.ts`. `subscription-preview-token.service.ts` and
command/policy callers do not change.

#### Byte-Compatible Contract

The cut must preserve:

- all eight payload interfaces, sixteen public sign/verify functions, error
  codes and exported names;
- token shape `v1.<base64url(JSON)>.<base64url(HMAC-SHA256)>`;
- the eight existing domain strings and signature input `${domain}.${body}`;
- minimum secret length of 32 UTF-8 bytes, maximum token length 16,384 and the
  existing constant-time signature comparison;
- exact-key validation, UUID/money/units/fingerprint/status checks;
- the existing expiry boundary: expired only when
  `expiresAtSeconds < nowSeconds`;
- wrapper TTL, secret fallback and HTTP error mapping.

No validator condition is generalized or rewritten into a new schema engine.
The implementation is a mechanical move after characterization.

#### Tests

Create:

- `server/src/crm/commerce/subscription-preview-token.spec.ts`.

The suite must cover all eight round trips, pre-refactor golden token vectors,
tampering, cross-domain rejection, malformed/version/oversize/signature cases,
exact-key rejection, expiry boundaries and weak secrets. It must also assert
the facade export surface and that errors thrown through every domain are
instances of the single exported error class.

Focused existing integration suites exercise purchase, replacement,
cancellation, payment and schedule consumers. Backend typecheck and build are
mandatory.

### Lane C: Schedule Lesson-Details Presenter

#### Problem

`_showLessonDetails` in `schedule_widget_actions.dart` mixes API reads,
capability loading, parsing of dynamic lesson maps, name fallbacks, entity-link
projection, lifecycle action policy, navigation callbacks and sheet launch.
The method is approximately 251 lines and is one of the main contributors to
the file's complexity.

#### Design

Create
`lib/features/admin/presentation/widgets/schedule_lesson_details_presenter.dart`
with a pure `ScheduleLessonDetailsPresenter` and immutable
`ScheduleLessonDetailsPresentation`.

The widget computes or loads side-effectful inputs first:

- parsed lesson start and duration;
- settlement history, which remains widget-owned and bypasses the presenter;
- capability snapshot and `canOpen(EntityLink)` decision;
- current name lookup maps and conflicts.

The presenter receives the lesson map, ready start/duration/conflicts/name
lookups, an injected `now`, and the capability decision. It returns display
names, time range, references, lifecycle status, settlement issue and an
explicit action policy for settle/correction/planned-settlement.

The resulting flow is:

```text
ScheduleWidget
  -> MagicCrmService/capability provider reads
  -> pure ScheduleLessonDetailsPresenter
  -> unchanged showLessonDetailsSheet API
  -> existing widget-owned callbacks/navigation
```

`_showLessonDetails` keeps `mounted` guards, history failure handling,
navigation, edit/cancel/settle callbacks and sheet launch. A capability-load
failure remains fail-closed for linked rows while lesson details remain
readable.

The following remain unchanged:

- `lesson_details_sheet.dart` public signature;
- `LessonDecisionController` and mutation flows;
- `_fetchAll`, `_fetchDayLessons`, schedule search and date navigation;
- `MagicCrmService`, NestJS routes/DTOs and lesson command envelopes.

#### Tests

Create:

- `test/features/schedule/schedule_lesson_details_presenter_test.dart`.

The pure tests cover:

- student/lead/teacher/room/group/branch fallbacks;
- snake_case and camelCase lifecycle keys;
- exact `EntityLink` types, variants, focus and filters;
- unavailable links when capability state is missing or denied;
- settlement recovery, correction and future planned-settlement policy with a
  fixed `now`.

Existing schedule redesign and lesson-link affordance tests remain green.

## Parallel Ownership and Integration

Implementation uses isolated worktrees and three disjoint lane branches. No
agent edits another lane, the root checkout, shared lockfiles or generated
RepoWise data.

| Lane | Owned production files | Shared production files allowed |
|---|---|---|
| Payment | `client_payment_form.dart` | none |
| Token | facade plus four token modules | none |
| Schedule | `schedule_widget_actions.dart`, `schedule_widget.dart`, new presenter | none |

Each implementer writes tests first, makes one focused lane commit and returns
the commit SHA. The integrator reviews and cherry-picks lane commits. Only the
integrator runs `repowise update --index-only`, Sentrux scans, combined tests
and final commits.

The requested ten-specialist team runs in waves because the environment has
four active slots including the coordinator:

1. specialists 1-3: completed architecture/risk research;
2. specialists 4-6: three parallel lane implementers;
3. specialists 7-9: independent lane reviewers;
4. specialist 10: final integrated verification.

## Five-Hour Execution Clock

| Clock | Work |
|---|---|
| `0:00-0:20` | worktrees, baselines and lane RED characterization |
| `0:20-2:40` | three implementation lanes in parallel |
| `2:40-3:20` | three independent lane reviews |
| `3:20-4:00` | bounded corrections and focused reruns |
| `4:00-4:40` | integrated Flutter/backend gates, reindex and Sentrux |
| `4:40-5:00` | final verifier, evidence and clean-worktree check |

At `2:40`, a lane that is not focused-test green is removed from the
integration candidate rather than allowed to consume another lane's gate time.
No partial lane is merged. At `4:40`, any unresolved Critical/Important review
finding or broken frozen contract removes that lane from the final candidate.

## Verification

### Flutter Payment

```powershell
flutter test test/features/commerce/client_payment_form_test.dart test/features/commerce/client_payments_tab_test.dart
```

### Flutter Schedule

```powershell
flutter test test/features/schedule/schedule_lesson_details_presenter_test.dart test/features/admin/schedule_redesign_test.dart test/features/navigation/lesson_link_affordance_test.dart
```

### Backend Token

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-preview-token.spec.ts src/architecture/export-surface.contract.spec.ts
npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-cancel-postgres.integration.spec.ts src/crm/commerce/subscription-issue-postgres.integration.spec.ts src/crm/commerce/subscription-replace-postgres.integration.spec.ts src/crm/schedule/completion-worker-postgres.integration.spec.ts src/crm/schedule/lesson-write-parity.integration.spec.ts src/crm/schedule/reschedule-postgres.integration.spec.ts src/crm/schedule/schedule-plan-postgres.integration.spec.ts
npm --prefix server run typecheck
npm --prefix server run build
```

### Integrated Structural Gate

```powershell
flutter analyze
git diff --check
repowise update --index-only
```

After reindex, record targeted RepoWise health/risk and run the required
Sentrux rescan/health/rules comparison. No new production god/brain marker,
dependency cycle, security signal or unexplained Sentrux regression is
accepted.

## Acceptance Criteria

1. Payment identity tests prove same-payload stability and changed-payload
   rotation for all five form owners; public submissions and service/API
   boundaries are unchanged.
2. Pre-refactor golden preview tokens verify through the post-refactor facade;
   all existing exports and one error-class identity are preserved.
3. `_showLessonDetails` becomes a thin orchestration method, with projection
   and action policy covered by deterministic pure tests.
4. `_PaymentMutationSession` and the new schedule presenter have max CCN at
   most 10. Mechanically moved token validators preserve their exact
   conditions and do not increase CCN. No new production owner has a
   god/brain marker, and existing targeted health does not regress.
5. Focused suites, backend typecheck/build, Flutter analyze, RepoWise and
   Sentrux gates pass; final worktree is clean.

## Explicit Exclusions

- No refactor of `client_create_dialogs.dart` or `client_card_student.dart` in
  this sprint.
- No full split of `client_payment_form.dart`.
- No generic token/schema framework or token-format/version change.
- No `_fetchAll`, day-fetch, search, navigation or lesson-mutation refactor.
- No route, DTO, provider, database, migration, product-rule, UI-copy, theme,
  deployment or production-data change.

## Rollback

Each lane is source-only and independently revertible. If a lane fails its
timebox or gate, omit or revert only that lane commit. There are no migrations,
environment changes or persisted-format changes to roll back. Golden token
verification is the mandatory proof that the backend lane can read tokens
created before the refactor.
