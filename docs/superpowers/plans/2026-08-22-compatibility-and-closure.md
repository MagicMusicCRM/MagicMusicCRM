# Compatibility and Cleanup Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every remaining version/legacy name an explicit contract, reorganize historical tests by capability, remove confirmed dead exports, and close the cleanup with repository-wide RepoWise and Sentrux gates.

**Architecture:** Operational versioned contracts move under visible migration/rollout boundaries without changing identifiers. Live map-shape compatibility is isolated in named adapters with removal conditions; tests describe capabilities rather than release phases, and deletion is limited to RepoWise-confirmed safe exports.

**Tech Stack:** Flutter/Dart, NestJS/TypeScript, PostgreSQL migration CLIs, Jest, Flutter tests, RepoWise, Sentrux.

**Spec:** `docs/superpowers/specs/2026-08-22-systematic-codebase-cleanup-design.md`

**Depends on:** Foundation, Shared Tasks, Reporting, and Semantic Part cleanup plans completed.

## Global Constraints

- Do not rename SQL functions, HTTP routes, persisted values, environment variables, rollout modes, idempotency fields, or release manifest paths.
- Migration CLIs remain dry-run by default; this plan never supplies `--apply`, deploys, or touches production data.
- A compatibility adapter is removed only at zero live consumers; otherwise it remains registered with `owner` and `remove_when`.
- Before every deletion call RepoWise `get_risk` on the exact files and verify the symbol against live source. One task per commit.
- If a committed cut fails its gate, stop and use a separate `git revert` or corrective commit; never use `git reset --hard`.
- Run relevant tests, RepoWise index update, and Sentrux check/gate after every task. Final quality must exceed `4892`, depth must be at most `15`, and rules must be `PASS`.

---

### Task 1: Put legitimate versions under migration and rollout boundaries

**Files:**
- Move `server/src/platform/v7-commerce-data.ts` to `server/src/migration/commerce/v7/commerce-data.ts`.
- Move `server/src/migration/v3-import-utils.ts` and its spec to `server/src/migration/import/v3/`.
- Move `server/src/platform/v4-{backfill,migrate-dry-run,preflight,reconcile,shadow-compare}*` to `server/src/platform/rollout/v4/`.
- Move `server/src/platform/v4-domain-flags.ts` and spec to `server/src/platform/rollout/v4/domain-flags.ts`.
- Move `server/src/access-control/v4-access-coverage.ts` to `server/src/access-control/rollout/v4/access-coverage.ts`.
- Create: `server/src/platform/rollout/versioned-boundaries.spec.ts`.
- Modify imports and `server/package.json` script paths.
- Modify: `tool/naming_exceptions.json`.

**Interfaces:**
- Preserves `backfillV7Commerce`, `reconcileV7Commerce`, `V4DomainFlagsService`, every current CLI argument, exit code, env variable, and SQL function string.
- Produces explicit filesystem boundaries only.

- [ ] **Step 1: Add path and contract assertions**

Create `server/src/platform/rollout/versioned-boundaries.spec.ts`:

```ts
import { readFileSync } from "node:fs";

it("keeps versioned contracts inside rollout or migration boundaries", () => {
  const pkg = JSON.parse(readFileSync("package.json", "utf8"));
  expect(pkg.scripts["v7:reconcile"]).toContain(
    "src/migration/commerce/v7/commerce-data.ts",
  );
  expect(pkg.scripts["v4:preflight"]).toContain(
    "src/platform/rollout/v4/preflight.ts",
  );
});
```

- [ ] **Step 2: Run and verify RED**

```powershell
npm --prefix server test -- --runTestsByPath src/platform/rollout/versioned-boundaries.spec.ts
```

Expected: Jest cannot resolve the new test/path.

- [ ] **Step 3: Move files and update imports/scripts without renaming contracts**

```json
{
  "v4:preflight": "ts-node src/platform/rollout/v4/preflight.ts",
  "v4:reconcile": "ts-node src/platform/rollout/v4/reconcile.ts",
  "v7:backfill": "ts-node src/migration/commerce/v7/commerce-data.ts --apply",
  "v7:reconcile": "ts-node src/migration/commerce/v7/commerce-data.ts"
}
```

Set `v4:backfill`, `v4:migrate:dry-run`, `v4:preflight`, `v4:reconcile`, and
`v4:shadow-compare` to `src/platform/rollout/v4/<script>.ts`; set
`v4:access-coverage` to
`src/access-control/rollout/v4/access-coverage.ts`. Preserve strings such as
`app.backfill_v7_commerce()`, `app.reconcile_v7_commerce()`,
`V4_ACCESS_MODE`, `legacy|shadow|v4`, and `MIGRATION_DATABASE_URL` byte-for-byte.

- [ ] **Step 4: Verify TypeScript, operational tests, and quality**

```powershell
npm --prefix server run typecheck
npm --prefix server test -- --runTestsByPath src/platform/rollout/versioned-boundaries.spec.ts src/platform/rollout/v4/domain-flags.spec.ts src/platform/rollout/v4/reconcile.spec.ts src/platform/rollout/v4/shadow-compare.spec.ts src/migration/import/v3/v3-import-utils.spec.ts
npm --prefix server run test:commerce-v4
dart run tool/check_repository_naming.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: paths are explicit, all versioned identifiers remain, and no CLI is executed against a database.

- [ ] **Step 5: Commit**

```powershell
git add -- server/src server/package.json tool/naming_exceptions.json
git commit -m "refactor(platform): isolate versioned rollout tooling"
```

### Task 2: Contain CRM legacy map normalization

**Files:**
- Rename: `lib/core/services/magic_crm_service_mappers.dart` to `magic_crm_service_legacy_map_adapter.dart`.
- Modify: `lib/core/services/magic_crm_service.dart` part directive.
- Create: `test/core/services/magic_crm_legacy_map_adapter_test.dart`.
- Modify: `tool/naming_exceptions.json`.

**Interfaces:**
- Preserves every existing private mapper signature and returned map key.
- Produces an explicit compatibility boundary registered with removal condition: all `MagicCrmService` consumers use typed models directly.

- [ ] **Step 1: Add representative map-shape tests**

```dart
test('legacy lead map keeps ids, labels and snake_case keys', () {
  final result = mapLeadResponseToLegacyShape(typedLeadFixture);
  expect(result, containsPair('id', typedLeadFixture.id));
  expect(result, contains('status_id'));
  expect(result, contains('custom_data'));
});
```

Use the actual mapper names from the part file and cover one representative
payload for Lead, Lesson, Payment, Subscription, Student balance, and family.
Tests must assert exact current keys, null handling, and nested list shapes.

- [ ] **Step 2: Run and verify the new import is RED**

```powershell
flutter test test/core/services/magic_crm_legacy_map_adapter_test.dart
```

Expected: compilation fails until the renamed part and test hook exist.

- [ ] **Step 3: Rename the part and document the boundary**

```dart
part of 'magic_crm_service.dart';

/// Compatibility boundary for presentation consumers that still expect the
/// historical snake_case map contract.
/// Remove when every MagicCrmService consumer reads typed domain models.
```

Do not rename mapper functions in this commit. Expose test-only behavior through
existing public service calls or `@visibleForTesting` wrappers; never duplicate mapper logic in tests.

- [ ] **Step 4: Verify all CRM model/service tests and quality**

```powershell
rg -n "magic_crm_service_mappers" lib test
dart format lib/core/services/magic_crm_service_legacy_map_adapter.dart test/core/services/magic_crm_legacy_map_adapter_test.dart
flutter test test/core/services/magic_crm_legacy_map_adapter_test.dart test/core/services/magic_crm_service_test.dart test/features/crm
flutter analyze lib/core/services/magic_crm_service.dart lib/core/services/magic_crm_service_legacy_map_adapter.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: old vague mapper filename has zero hits and payload compatibility is unchanged.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/core/services/magic_crm_service.dart lib/core/services/magic_crm_service_legacy_map_adapter.dart lib/core/services/magic_crm_service_mappers.dart test/core/services/magic_crm_legacy_map_adapter_test.dart tool/naming_exceptions.json
git commit -m "refactor(crm): name legacy map compatibility boundary"
```

### Task 3: Extract Messenger, Profile, and Commerce compatibility adapters

**Files:**
- Create: `lib/core/compat/messenger_legacy_map_adapter.dart`
- Create: `lib/core/compat/profile_admin_legacy_map_adapter.dart`
- Create: `lib/core/compat/commerce_legacy_map_adapter.dart`
- Create: `test/core/compat/legacy_map_adapters_test.dart`
- Modify: `lib/core/services/magic_messenger_service.dart`
- Modify: `lib/core/services/magic_profile_admin_service.dart`
- Modify: `lib/core/models/commerce_projection.dart`
- Modify: `lib/core/theme/telegram_colors.dart`, `lib/core/theme/app_theme.dart`, `lib/core/theme/design_tokens.dart`, `lib/core/theme/lesson_state_palette.dart`, `lib/core/services/chat_attachment_service.dart`, `lib/core/services/notification_service.dart`, `lib/core/router/app_router.dart`, `lib/core/widgets/telegram/message_bubble.dart`, `lib/features/manager/presentation/providers/leads_providers.dart`, and `tool/naming_exceptions.json` when their compatibility names are confirmed live.

**Interfaces:**
- Produces `MessengerLegacyMapAdapter`, `ProfileAdminLegacyMapAdapter`, and `CommerceLegacyMapAdapter` with pure map-in/map-out methods.
- Service public return types and map shapes remain unchanged.

- [ ] **Step 1: Add adapter parity tests**

```dart
test('messenger adapter normalizes summary and API chat identically', () {
  final adapter = MessengerLegacyMapAdapter();
  expect(
    adapter.chat(chatSummaryFixture),
    adapter.chat(chatApiFixtureWithEquivalentValues),
  );
});

test('commerce adapter preserves legacy funding mode and linkage ids', () {
  final map = CommerceLegacyMapAdapter().subscription(subscriptionFixture);
  expect(map['funding_mode'], 'legacy');
  expect(map['payment_id'], subscriptionFixture.paymentId);
});
```

Cover chat, message, member, channel, permission, post, profile, profile note,
subscription, payment, and balance shapes.

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/core/compat/legacy_map_adapters_test.dart
```

Expected: compilation fails because adapter classes do not exist.

- [ ] **Step 3: Move pure conversions and normalize remaining terminology**

```dart
abstract interface class MessengerLegacyMapAdapter {
  Map<String, dynamic> chat(Map<String, dynamic> source);
  Map<String, dynamic> message(Map<String, dynamic> source);
  Map<String, dynamic> chatMember(Map<String, dynamic> source);
  Map<String, dynamic> channel(Map<String, dynamic> source);
  Map<String, dynamic> channelPermission(Map<String, dynamic> source);
  Map<String, dynamic> channelPost(Map<String, dynamic> source);
}
```

Create `DefaultMessengerLegacyMapAdapter` by moving the complete bodies of
`_legacyChat`, `_legacyMessage`, `_legacyChatMember`, `_legacyChannel`,
`_legacyChannelPermission`, and `_legacyChannelPost`. The Profile adapter owns
the complete `_legacyProfile` and `_legacyProfileNote` bodies. The Commerce
adapter owns `toLegacyBalance`, `toLegacyMap`, and `toLegacyPayment` bodies;
the projection calls the adapter and retains its current public typed results.

Services own transport only and delegate conversions. Rename internal non-contract
parameters such as `legacyStatus` to `rawStatus` and legacy provider aliases to
capability names when `rg` proves they are internal. Keep and register actual
contracts: router redirects, notification backward-compatible entry points,
`funding_mode='legacy'`, Supabase-reference cutover parsing, updater bridge, and
theme aliases that still have live consumers. Delete an alias only after RepoWise
risk plus live `rg` show zero consumers.

- [ ] **Step 4: Verify adapters and every remaining legacy occurrence**

```powershell
rg -n -i "legacy|backward compat|deprecated" lib server/src --glob '!**/*.spec.ts'
dart format lib/core/compat lib/core/services/magic_messenger_service.dart lib/core/services/magic_profile_admin_service.dart lib/core/models/commerce_projection.dart test/core/compat
flutter test test/core/compat/legacy_map_adapters_test.dart test/core/services/magic_messenger_service_test.dart test/core/services/magic_profile_admin_service_test.dart test/core/services/magic_crm_service_test.dart
flutter analyze lib/core/compat lib/core/services lib/core/models/commerce_projection.dart
dart run tool/check_repository_naming.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: every remaining `legacy` hit is a registered live contract or an
explicit adapter; no unexplained temporary terminology remains.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/core/compat lib/core/services lib/core/models/commerce_projection.dart test/core/compat tool/naming_exceptions.json
git commit -m "refactor(compat): isolate legacy map adapters"
```

### Task 4: Replace historical test buckets with capability paths

**Files:**
- Move all tracked files under `test/features/v4`, `test/features/v6`, `test/features/v7`, `test/features/s8`.
- Rename version-prefixed `integration_test/*` files.
- Modify all test-to-test imports and `tool/naming_exceptions.json`.

**Interfaces:**
- Test bodies and production imports are unchanged; only ownership paths and test descriptions mentioning implementation phases are normalized.

- [ ] **Step 1: Bind the naming policy to tracked test paths**

```dart
test('tracked active tests are grouped by capability', () {
  final testPaths = trackedDartSources()
      .where((path) => path.startsWith('test/features/'));
  final violations = findNamingViolations(
    paths: testPaths,
    exceptions: const [],
  );
  expect(violations, isEmpty);
});
```

- [ ] **Step 2: Run and verify RED after removing bucket exceptions locally**

```powershell
flutter test test/architecture/naming_policy_test.dart
```

Expected: current version directories are reported.

- [ ] **Step 3: Apply the exact capability map**

```text
test/features/access:
  access_editor_roles, capability_shell
test/features/workspace:
  context_transition_matrix, desktop_tab_controls,
  desktop_workspace_controller, workspace_persistence_logout,
  canonical_app_location, desktop_context_bar, production_workspace_mount,
  typed_entity_navigation_policy, accessibility_inventory, visual_baseline
test/features/navigation:
  entity_link_registry, client_workspace_route, lesson_link_affordance
test/features/schedule:
  lesson_form, lesson_state_palette, schedule_regression,
  teacher_schedule_read_only, client_schedule_calendar,
  preferred_schedule_editor, recurring_schedule_plan_section,
  lesson_decision_flow
test/features/crm:
  client_card_roles, client_forms, client_schedule_navigation,
  student_funnel_editor, client_card_action_inventory,
  client_internal_context
test/features/commerce:
  client_finance_roles, client_payment_form, client_payments_tab,
  subscription_cancel_form, subscription_issue_form,
  subscription_replace_form, subscription_package_catalog
test/features/settings:
  crm_configuration_workspace, system_settings_workspace,
  branch_lifecycle_dialog, data_quality_deletion_lifecycle,
  group_lifecycle_dialog, person_lifecycle_dialog,
  reference_catalog_lifecycle, room_lifecycle_dialog,
  room_management_user_flow
test/features/messenger:
  homework_attachment_flow
test/features/recovery:
  uat_116_state_recovery
test/features/search:
  stable_server_search
```

Files already moved by earlier plans are not duplicated. Rename integration
tests by removing `v4_`, `v6_`, `v7_`, or `stage7_` and keep the capability
basename, for example `v7_expense_lifecycle_device_test.dart` becomes
`expense_lifecycle_device_test.dart`. Update explicit imports before deleting old paths.

- [ ] **Step 4: Run full Flutter test-path gates**

```powershell
rg -n "test/features/(v4|v6|v7|s8)|integration_test/(v4|v6|v7|stage7)_" test integration_test lib
flutter test
flutter analyze
dart run tool/check_repository_naming.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: `rg` returns no active test generation path; Flutter tests/analyzer pass.

- [ ] **Step 5: Commit**

```powershell
git add -- test integration_test tool/naming_exceptions.json
git commit -m "test(architecture): group suites by capability"
```

### Task 5: Delete confirmed dead exports and run final gates

**Files:**
- Modify exact source files containing the RepoWise-confirmed exports listed below.
- Modify tests only when needed to preserve public contract assertions.
- Modify: `tool/naming_exceptions.json`.

**Interfaces:**
- Removes unused exports only; runtime behavior and reachable symbols are unchanged.

- [ ] **Step 1: Reconfirm the deletion set with RepoWise and live source**

Cleanup candidates:

```text
server/src/crm/crm-mappers.ts:
  diffTaskRows, toTaskDto, toTaskHistoryDto
server/src/crm/leads.service.ts:
  LeadBoardColumnDto
server/src/crm/dto/upsert-expense.dto.ts:
  EXPENSE_CATEGORIES
server/src/crm/dto/student-funnel.dto.ts:
  CLIENT_PIPELINE_STYLES, StudentFunnelQuery, CLIENT_PIPELINE_TYPES
server/src/notifications/dto/update-notification-preference.dto.ts:
  NOTIFICATION_EVENT_TYPES, NOTIFICATION_PREFERENCE_ROLES
server/src/crm/age.ts:
  BIRTHDAY_KEY, AGE_KEY
server/src/crm/appeal-date.ts:
  HOLLIHOP_APPEAL_KEY
server/src/crm/subscription-preview-token.service.ts:
  SUBSCRIPTION_PREVIEW_TTL_SECONDS
server/src/platform/rollout/v4/domain-flags.ts:
  V4_DOMAINS
```

Call RepoWise `get_dead_code(kind="unused_export", safe_only=true,
min_confidence=0.8)` and `get_risk` on every containing file. Stop if any
candidate is no longer high-confidence or has a live `rg` consumer.

- [ ] **Step 2: Add an export-surface regression before deletion**

```ts
it("keeps required CRM mapper exports available", () => {
  expect(typeof requiredMapperExport).toBe("function");
});
```

Use actual required neighboring exports from each touched module; do not assert
the presence of a symbol being deleted.

- [ ] **Step 3: Remove only reconfirmed symbols and stale imports**

Do not delete any whole file: the approved baseline contains zero
high-confidence unreachable production files. Preserve internal helpers if they
are still called locally even when their export modifier is removed.

- [ ] **Step 4: Run repository-wide closure gates**

```powershell
npm --prefix server run typecheck
npm --prefix server test
flutter test
flutter analyze
dart run tool/check_repository_naming.dart
repowise update --index-only
sentrux check
sentrux gate
git status --short
```

Expected: all gates pass; Sentrux quality is greater than `4892`, depth is at
most `15`, rules are `PASS`; no unregistered ambiguous naming debt remains.

- [ ] **Step 5: Commit closure evidence in code changes only**

```powershell
git add -- server/src tool/naming_exceptions.json
git commit -m "refactor(architecture): close confirmed cleanup debt"
```

Do not create a separate report unless a product rule, runbook, architecture
decision, or verified release status changed.
