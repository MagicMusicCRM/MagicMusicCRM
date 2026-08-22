# Cleanup Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent new ambiguous names, remove the historical `v7` UI boundary, and give shared navigation, form-exit, auth, and client-card primitives capability-based names without changing behavior.

**Architecture:** RepoWise remains the navigation/risk layer and Sentrux is the mandatory structural-quality loop. Existing UI primitives move behind direct semantic imports; workspace-specific dirty-exit behavior is separated from the generic form controller, and no compatibility alias survives a completed rename.

**Tech Stack:** Flutter, Dart, Riverpod, Flutter tests, RepoWise, Sentrux.

**Spec:** `docs/superpowers/specs/2026-08-22-systematic-codebase-cleanup-design.md`

**Depends on:** No cleanup plan; execute this plan first.

## Global Constraints

- Preserve all current UI behavior, Russian text, Deep Charcoal & Sophisticated Gold tokens, keys, routes, RBAC, and service/provider boundaries.
- Do not rename live API paths, PostgreSQL functions, migration identifiers, rollout flags, persisted namespaces, or release channels.
- One behavior-neutral cut per commit; never mix a rename with unrelated formatting or product changes.
- If a committed cut fails its gate, stop and use a separate `git revert` or corrective commit; never use `git reset --hard`.
- Before every task record `sentrux check` and `sentrux gate`; repeat both after the task. Rules must remain `PASS`, quality must not regress without owner approval, and dependency depth must not increase without evidence.
- After every structural task run `repowise update --index-only`; verify low-confidence RepoWise output against live source.

---

### Task 1: Add the naming-policy guardrail

**Files:**
- Create: `tool/src/naming_policy.dart`
- Create: `tool/check_repository_naming.dart`
- Create: `tool/naming_exceptions.json`
- Create: `test/architecture/naming_policy_test.dart`

**Interfaces:**
- Consumes: tracked paths/source returned by `git ls-files` and the JSON exception registry.
- Produces: `NamingViolation`, `NamingPolicyException`, `trackedDartSources()`, `findNamingViolations(...)`, `findSymbolViolations(...)`, and a CLI that exits `0` only when every finding is absent or registered.

- [ ] **Step 1: Write failing policy tests**

```dart
import '../../tool/src/naming_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects generation and mechanical part names in production', () {
    final violations = findNamingViolations(
      paths: const [
        'lib/features/tasks/v9/tasks_panel.dart',
        'lib/features/tasks/tasks_view_a.dart',
        'lib/features/tasks/new_tasks.dart',
      ],
      exceptions: const [],
    );
    expect(violations.map((item) => item.rule), containsAll(<String>{
      'production-generation-name',
      'mechanical-part-suffix',
      'temporary-name',
    }));
  });

  test('accepts a documented migration exception', () {
    const exception = NamingPolicyException(
      target: 'server/src/migration/commerce/v7/',
      category: 'migration',
      reason: 'Calls versioned PostgreSQL reconciliation functions.',
      owner: 'platform',
      removeWhen: 'V7 commerce migration is formally retired.',
    );
    expect(
      findNamingViolations(
        paths: const ['server/src/migration/commerce/v7/reconcile.ts'],
        exceptions: const [exception],
      ),
      isEmpty,
    );
  });

  test('rejects generation symbols and historical test buckets', () {
    expect(
      findSymbolViolations(
        sources: const {'lib/login.dart': 'class _V7Field {}'},
        exceptions: const [],
      ).single.rule,
      'production-generation-symbol',
    );
    expect(
      findNamingViolations(
        paths: const ['test/features/v9/example_test.dart'],
        exceptions: const [],
      ).single.rule,
      'test-generation-bucket',
    );
  });
}
```

- [ ] **Step 2: Run the tests and verify RED**

```powershell
flutter test test/architecture/naming_policy_test.dart
```

Expected: compilation fails because `tool/src/naming_policy.dart` does not exist.

- [ ] **Step 3: Implement the pure policy and CLI**

```dart
class NamingPolicyException {
  const NamingPolicyException({
    required this.target,
    required this.category,
    required this.reason,
    required this.owner,
    required this.removeWhen,
  });
  final String target;
  final String category;
  final String reason;
  final String owner;
  final String removeWhen;
}

class NamingViolation {
  const NamingViolation(this.path, this.rule);
  final String path;
  final String rule;
}

List<NamingViolation> findNamingViolations({
  required Iterable<String> paths,
  required List<NamingPolicyException> exceptions,
}) {
  final allowed = exceptions.map((item) => item.target).toList();
  bool covered(String path) => allowed.any(path.startsWith);
  final generation = RegExp(r'(^|[/_-])v\d+([/_.-]|$)', caseSensitive: false);
  final partSuffix = RegExp(r'_[abc]\.dart$', caseSensitive: false);
  final temporary = RegExp(
    r'(^|[/_])(old|new|temp|tmp)([/_.-]|$)',
    caseSensitive: false,
  );
  final testBucket = RegExp(r'^test/features/(v\d+|s\d+)/');
  bool productionSource(String path) =>
      path.startsWith('lib/') || path.startsWith('server/src/');
  return [
    for (final path in paths.where(productionSource))
      if (!covered(path) && generation.hasMatch(path))
        NamingViolation(path, 'production-generation-name'),
    for (final path in paths.where((path) => path.startsWith('lib/')))
      if (!covered(path) && partSuffix.hasMatch(path))
        NamingViolation(path, 'mechanical-part-suffix'),
    for (final path in paths.where(productionSource))
      if (!covered(path) && temporary.hasMatch(path))
        NamingViolation(path, 'temporary-name'),
    for (final path in paths.where(testBucket.hasMatch))
      if (!covered(path)) NamingViolation(path, 'test-generation-bucket'),
  ];
}

List<NamingViolation> findSymbolViolations({
  required Map<String, String> sources,
  required List<NamingPolicyException> exceptions,
}) {
  final generationSymbol = RegExp(
    r'\b(?:_?V\d+[A-Z][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*V\d+(?:[A-Z][A-Za-z0-9_]*)?)\b',
  );
  return [
    for (final entry in sources.entries)
      for (final match in generationSymbol.allMatches(entry.value))
        if (!exceptions.any((item) =>
            item.target == '${entry.key}::${match.group(0)}'))
          NamingViolation(
            '${entry.key}::${match.group(0)}',
            'production-generation-symbol',
          ),
  ];
}
```

The CLI decodes every JSON entry, rejects empty `reason`, `owner`, or
`remove_when`, rejects exceptions matching no tracked path, prints one
`path: rule` per violation, and sets `exitCode = 1` on error. Seed the registry
with current UI generation debt, `_a/_b` files, four historical test buckets,
V3/V4 rollout files, V7 commerce migration, `mmcrm.v3`, and `latest-v2.json`.
Every cleanup-debt entry names the milestone that removes it.

- [ ] **Step 4: Verify policy and quality gates**

```powershell
dart format tool/src/naming_policy.dart tool/check_repository_naming.dart test/architecture/naming_policy_test.dart
flutter test test/architecture/naming_policy_test.dart
dart run tool/check_repository_naming.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: tests pass, CLI exits `0`, RepoWise indexes HEAD, Sentrux rules remain `PASS`.

- [ ] **Step 5: Commit**

```powershell
git add -- tool/src/naming_policy.dart tool/check_repository_naming.dart tool/naming_exceptions.json test/architecture/naming_policy_test.dart
git commit -m "chore(architecture): enforce repository naming policy"
```

### Task 2: Split generic and workspace dirty-exit behavior

**Files:**
- Create: `lib/core/forms/dirty_form_exit.dart`
- Create: `lib/core/workspace/workspace_dirty_form_exit.dart`
- Modify: `lib/core/workspace/production_workspace_host.dart`
- Modify: `lib/features/messenger/presentation/screens/messenger_screen.dart`
- Modify: `lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart`
- Modify: `test/core/widgets/dirty_form_exit_test.dart`
- Create: `test/core/workspace/workspace_dirty_form_exit_test.dart`
- Delete: `lib/core/widgets/v7/dirty_form_exit.dart`

**Interfaces:**
- Produces unchanged generic API: `DirtyFormExitReason`, `DirtyFormExitDecision`, `DirtyFormExitController`, `DirtyFormExitScope`, `showDirtyFormExitDialog`.
- Produces unchanged workspace adapter: `Future<bool> requestWorkspaceDirtyExit(BuildContext context, {required DirtyFormExitReason reason})`.

- [ ] **Step 1: Split characterization tests by responsibility**

The generic test imports only `core/forms/dirty_form_exit.dart`. The workspace
test imports both new files and retains the existing logout assertion:

```dart
final canLogout = await requestWorkspaceDirtyExit(
  context,
  reason: DirtyFormExitReason.logout,
);
expect(canLogout, isFalse);
expect(workspaceController.state.loggedOut, isFalse);
```

Add a source-boundary assertion:

```dart
test('generic dirty form code does not import workspace', () {
  final source = File('lib/core/forms/dirty_form_exit.dart').readAsStringSync();
  expect(source, isNot(contains('/workspace/')));
});
```

- [ ] **Step 2: Run the new paths and verify RED**

```powershell
flutter test test/core/widgets/dirty_form_exit_test.dart test/core/workspace/workspace_dirty_form_exit_test.dart
```

Expected: compilation fails because the new production files do not exist.

- [ ] **Step 3: Move code without aliases**

`core/forms/dirty_form_exit.dart` contains the enum, dialog, controller, and
scope only. `core/workspace/workspace_dirty_form_exit.dart` contains exactly:

```dart
Future<bool> requestWorkspaceDirtyExit(
  BuildContext context, {
  required DirtyFormExitReason reason,
}) async {
  final workspace = WorkspaceNavigationScope.maybeOf(context);
  if (workspace == null || workspace.controller.state.loggedOut) return true;
  final controller = workspace.controller;
  return controller.resolveDirtyTab(
    controller.state.activeTabId,
    resolveDirty: (_) async => switch (await showDirtyFormExitDialog(context)) {
      DirtyFormExitDecision.save => DirtyCloseDecision.save,
      DirtyFormExitDecision.discard => DirtyCloseDecision.discard,
      DirtyFormExitDecision.cancel || null => DirtyCloseDecision.cancel,
    },
    saveDirty: controller.saveDirtyForms,
    discardDirty: controller.discardDirtyForms,
  );
}
```

Update every importer directly; do not leave a forwarding export under `v7/`.

- [ ] **Step 4: Verify tests, graph, and Sentrux delta**

```powershell
dart format lib/core/forms/dirty_form_exit.dart lib/core/workspace/workspace_dirty_form_exit.dart test/core/widgets/dirty_form_exit_test.dart test/core/workspace/workspace_dirty_form_exit_test.dart
flutter test test/core/widgets/dirty_form_exit_test.dart test/core/workspace/workspace_dirty_form_exit_test.dart test/features/messenger/tasks_navigation_test.dart
flutter analyze lib/core/forms/dirty_form_exit.dart lib/core/workspace/workspace_dirty_form_exit.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: workspace dependencies disappear from the generic form boundary;
Sentrux rules pass and depth does not exceed the pre-task baseline.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/core/forms/dirty_form_exit.dart lib/core/workspace/workspace_dirty_form_exit.dart lib/core/workspace/production_workspace_host.dart lib/features/messenger/presentation/screens/messenger_screen.dart lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart test/core/widgets/dirty_form_exit_test.dart test/core/workspace/workspace_dirty_form_exit_test.dart lib/core/widgets/v7/dirty_form_exit.dart
git commit -m "refactor(forms): isolate workspace dirty exit"
```

### Task 3: Give the navigation shell a semantic API

**Files:**
- Create: `lib/core/navigation/responsive_navigation_shell.dart`
- Modify: `lib/core/navigation/crm_nav_rbac.dart`
- Modify: `lib/core/workspace/production_workspace_host.dart`
- Modify: `lib/features/client/presentation/screens/client_dashboard_screen.dart`
- Rename: `test/core/widgets/v7_nav_shell_test.dart` to `test/core/navigation/responsive_navigation_shell_test.dart`
- Modify affected tests returned by `rg -l 'V7Nav' test integration_test`
- Delete: `lib/core/widgets/v7/v7_nav_shell.dart`

**Interfaces:**
- Produces `ResponsiveNavDestination` with the existing constructor fields.
- Produces `ResponsiveNavigationShell({destinations, selectedIndex, onSelected, isDesktop})`.
- Produces `ResponsiveNavDestination crmDestinationForTab(...)` with the current parameters and switch behavior.

- [ ] **Step 1: Rename the focused test API first**

```dart
List<ResponsiveNavDestination> destinations(int count) => [
  for (var index = 0; index < count; index++)
    ResponsiveNavDestination(
      icon: Icons.circle_outlined,
      selectedIcon: Icons.circle,
      label: 'Раздел $index',
    ),
];
```

Retain the desktop rail, compact bottom bar, overflow, badge, and selection
assertions from the old test.

- [ ] **Step 2: Run the renamed test and verify RED**

```powershell
flutter test test/core/navigation/responsive_navigation_shell_test.dart
```

Expected: compilation fails because the semantic shell does not exist.

- [ ] **Step 3: Move the implementation and update symbols atomically**

```dart
class ResponsiveNavDestination {
  const ResponsiveNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;
}

class ResponsiveNavigationShell extends StatelessWidget {
  const ResponsiveNavigationShell({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.isDesktop,
  });
  final List<ResponsiveNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) =>
      isDesktop ? _buildRail(context) : _buildBar(context);
}
```

Move `_buildRail`, `_buildBar`, `_brand`, `_RailItem`, `_BottomItem`, and their
existing layout bodies from `v7_nav_shell.dart` without changing literals.
Rename private helper parameter types in the same file. Replace all `V7Nav*`
and `crmV7DestinationForTab` references; do not introduce deprecated typedefs.

- [ ] **Step 4: Verify all navigation callers and quality gates**

```powershell
rg -n "V7NavShell|V7NavDestination|crmV7DestinationForTab|v7_nav_shell" lib test integration_test
flutter test test/core/navigation/responsive_navigation_shell_test.dart test/features/v6/production_workspace_mount_test.dart test/features/v6/client_workspace_route_test.dart test/features/messenger/tasks_navigation_test.dart
flutter analyze lib/core/navigation/responsive_navigation_shell.dart lib/core/navigation/crm_nav_rbac.dart lib/core/workspace/production_workspace_host.dart lib/features/client/presentation/screens/client_dashboard_screen.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: `rg` returns no live hits, tests pass, Sentrux rules pass.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/core/navigation/responsive_navigation_shell.dart lib/core/navigation/crm_nav_rbac.dart lib/core/workspace/production_workspace_host.dart lib/features/client/presentation/screens/client_dashboard_screen.dart lib/core/widgets/v7/v7_nav_shell.dart test/core/navigation/responsive_navigation_shell_test.dart test/core/widgets/v7_nav_shell_test.dart test/features integration_test
git commit -m "refactor(navigation): name responsive shell by capability"
```

### Task 4: Remove the `v7` barrel and directory

**Files:**
- Move the remaining semantic primitives from `lib/core/widgets/v7/` to `lib/core/widgets/`.
- Modify every importer returned by `rg -l 'core/widgets/v7' lib test integration_test`.
- Delete: `lib/core/widgets/v7/v7.dart`
- Modify: `tool/naming_exceptions.json`

**Interfaces:**
- Preserves every existing primitive API except the navigation rename completed in Task 3.
- Produces direct imports such as `core/widgets/magic_sheet.dart` and `core/widgets/adaptive_surface.dart`.

- [ ] **Step 1: Make barrel-policy tests fail on current imports**

Add to `test/architecture/naming_policy_test.dart`:

```dart
test('production code does not import a wide UI barrel', () {
  final offenders = trackedDartSources().where((path) {
    final source = File(path).readAsStringSync();
    return source.contains('core/widgets/v7/v7.dart');
  }).toList();
  expect(offenders, isEmpty);
});
```

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/architecture/naming_policy_test.dart
```

Expected: failure listing current barrel importers.

- [ ] **Step 3: Move primitives and replace imports explicitly**

Move `adaptive_surface.dart`, `magic_desktop_scrollbar.dart`,
`magic_drawer.dart`, `magic_menu.dart`, `magic_page_state.dart`,
`magic_sheet.dart`, `magic_shimmer.dart`, and `magic_toast.dart` into
`lib/core/widgets/`. Update relative imports. Each consumer imports only the
symbols it uses; do not create another aggregate barrel.

- [ ] **Step 4: Verify no historical UI path remains**

```powershell
rg -n "core/widgets/v7|export '.*magic_|Shared v7 component" lib test integration_test
flutter test test/architecture/naming_policy_test.dart test/core/widgets/v7_components_test.dart test/core/widgets/adaptive_surface_policy_test.dart test/core/widgets/expandable_magic_sheet_test.dart
flutter analyze lib/core/widgets lib/features
dart run tool/check_repository_naming.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: no `core/widgets/v7` hit; focused tests and Sentrux rules pass.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/core/widgets lib/features test integration_test tool/naming_exceptions.json
git commit -m "refactor(ui): remove historical v7 component boundary"
```

### Task 5: Consolidate auth controls and remaining Flutter generation names

**Files:**
- Create: `lib/features/auth/presentation/widgets/auth_form_controls.dart`
- Create: `test/features/auth/auth_form_controls_test.dart`
- Modify six auth screens containing `_V7Field` or `_V7PrimaryButton`.
- Rename: `lib/features/crm/presentation/client_card/client_card_v4_api.dart` to `client_card_api.dart`
- Modify: `lib/features/crm/presentation/client_card/client_archive_button.dart`
- Modify: `lib/features/crm/presentation/client_card/teacher_client_card.dart`
- Modify: `lib/features/crm/presentation/client_forms/client_create_dialogs.dart`
- Move: `test/features/v4/client_card_roles_test.dart` to `test/features/crm/client_card/client_card_roles_test.dart`
- Modify imports in `integration_test/v7_client_archive_device_test.dart`
- Modify: `tool/naming_exceptions.json`

**Interfaces:**
- Produces `AuthField` and `AuthPrimaryButton` with the union of existing constructor parameters.
- Produces `ClientCardApi`, `clientCardApiProvider`, and `StudentCreateDialog` with unchanged behavior and payloads.

- [ ] **Step 1: Add shared-control and API contract tests**

```dart
testWidgets('AuthField preserves validation, suffix and disabled state', (tester) async {
  final controller = TextEditingController(text: 'bad');
  await tester.pumpWidget(testApp(AuthField(
    controller: controller,
    label: 'Почта',
    enabled: false,
    suffix: const Icon(Icons.mail),
    validator: (value) => value == 'ok' ? null : 'Ошибка',
  )));
  expect(find.text('Почта'), findsOneWidget);
  expect(find.byIcon(Icons.mail), findsOneWidget);
  expect(tester.widget<TextFormField>(find.byType(TextFormField)).enabled, isFalse);
});
```

Retain client archive tests asserting the exact unversioned routes
`/crm/clients/:type/:id/card`, `/crm/clients/archive/preview`, and
`/crm/clients/archive`.

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/auth/auth_form_controls_test.dart test/features/crm/client_card/client_card_roles_test.dart
```

Expected: compilation fails on the new types or paths.

- [ ] **Step 3: Extract controls and rename symbols without aliases**

```dart
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.enabled = true,
    this.autocorrect = true,
    this.suffix,
    this.validator,
    this.inputFormatters,
    this.onSubmitted,
    this.autofillHints,
  });
}

final clientCardApiProvider = Provider<ClientCardApi>(
  (ref) => ClientCardApi(ref.watch(magicApiClientProvider)),
);
```

Move the complete field build method from `login_screen.dart::_V7Field` and the
complete button build method from `login_screen.dart::_V7PrimaryButton`; the
other screen copies are removed only after constructor parity is verified.
Replace all ten private `_V7*` definitions and `_v7*Decoration` names. Rename
`StudentCreateDialogV4` only after `rg 'class StudentCreateDialog' lib` confirms
no class conflict. Do not rename `/analytics/v4` service methods or DTOs.

- [ ] **Step 4: Run complete foundation gates**

```powershell
rg -n "_V7|StudentCreateDialogV4|ClientCardV4|clientCardV4|core/widgets/v7" lib test integration_test
dart format lib/features/auth lib/features/crm/presentation/client_card lib/features/crm/presentation/client_forms test/features/auth test/features/crm/client_card
flutter test test/features/auth test/features/crm/client_card/client_card_roles_test.dart test/features/crm/client_card/client_card_family_access_test.dart
flutter analyze lib/features/auth lib/features/crm/presentation/client_card lib/features/crm/presentation/client_forms
dart run tool/check_repository_naming.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: no forbidden Flutter generation symbol remains outside contract
strings; Sentrux quality exceeds the plan-start baseline and rules pass.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/auth lib/features/crm/presentation/client_card lib/features/crm/presentation/client_forms test/features/auth test/features/crm/client_card test/features/v4/client_card_roles_test.dart integration_test/v7_client_archive_device_test.dart tool/naming_exceptions.json
git commit -m "refactor(ui): remove remaining generation component names"
```
