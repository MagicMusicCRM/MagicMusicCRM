# CRM Configuration Workspace Semantic Cut Design

**Date:** 2026-08-24

**Status:** Owner-approved design; implementation pending specification review

## Context

`lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart`
is the highest-weighted Flutter code-health target currently identified by
RepoWise. The file contains 2,543 NLOC and has a health score of 2.15/10 with a
weighted deficit of 14,877 points. Its state class spans 1,323 lines across 51
methods and is classified as a critical god class. The file is also a
97.8th-percentile increasing hotspot, has five bug fixes in the trailing six
months, and is maintained by one contributor.

The runtime blast radius is narrower than the history suggests. The public
surface consists of `CrmConfigurationRouteScreen`,
`CrmConfigurationWorkspace`, and `showCrmConfigurationWorkspace`; the barrel
file `client_forms.dart` exports that surface. The remaining direct dependents
are the CRM configuration widget and device tests. Most co-change partners are
historical rather than import dependencies.

Sentrux currently reports quality signal 0.4976, acyclicity 1.0, dependency
depth 13, and two passing architectural rules. This cut targets the file-level
god class, change scatter, and concentrated complexity. It does not claim to
lower the repository-wide dependency depth because the selected workspace is
not on the current longest chain.

RepoWise's automatic split groups are rejected. Names such as
`magic_api_error.dart`, `crm_configuration_workspace_part2.dart`, and
`lesson_state_palette.dart` do not describe the responsibilities they would
contain and would recreate the legacy naming ambiguity removed by the recent
systematic cleanup.

No recorded ADR governs this hotspot. The design follows the repository's
existing semantic Dart-library pattern used by `MessengerScreen`: one stateful
coordinator and semantic `part` files sharing a private library boundary.

## Goal

Split CRM configuration into cohesive, semantically named presentation and
snapshot components while preserving every API call, permission decision,
version transition, dirty-form behavior, migration result, widget key, and
user-visible workflow.

The stateful coordinator remains the only owner of mutable workspace state and
service orchestration. Extracted views receive immutable values and narrow
callbacks; editor dialogs collect and validate local input; snapshot utilities
perform deterministic data transformations.

## Non-goals

- No API endpoint, DTO, database, migration, environment, or production change.
- No new Riverpod controller, provider, repository, service, or configuration
  domain model.
- No change to capability names, role packages, branch scope, or backend RBAC.
- No redesign of the UI, labels, responsive behavior, keys, theme, or navigation.
- No simultaneous refactor of `ClientFormsApi`, the pipeline editor, client
  sources editor, system settings workspace, or backend CRM services.
- No compatibility facade or duplicate state path.

## Considered approaches

### 1. Semantic private UI parts plus an internal snapshot library — selected

Keep the workspace presentation in a single Dart library and move cohesive UI
and dialog components into semantically named `part` files. Presentation
components become private widgets with explicit constructor inputs and
callbacks instead of extensions that can freely mutate coordinator state.

Move pure snapshot transformations into a separate, directly testable internal
library that the workspace imports but the `client_forms.dart` barrel does not
export. This gives deterministic data logic a real import boundary without
making presentation implementation part of the feature's public API.

This preserves private symbols, avoids exposing package-internal implementation
classes, and matches an established repository pattern. Constructor contracts
still make data flow visible and testable even though the files share a Dart
library.

### 2. Independent Dart libraries

Import separate files containing public-but-unexported internal classes. This
creates stricter language-level boundaries, but forces formerly private dialog
and presentation types into a wider package namespace and increases rename and
import risk during a behavior-preserving cut.

### 3. Riverpod controller extraction

Move snapshot, version, selection, loading, and mutation state into a notifier.
This could create a stronger long-term state boundary, but it would change
lifecycle and concurrency semantics while the current code distinguishes a
server-side draft from locally unsaved edits. It is intentionally deferred
until the semantic split exposes whether a controller is still justified.

## Component boundary

The existing file keeps the public route/navigation surface and the private
stateful coordinator. It owns:

- capability reads and derived access decisions;
- branches, selected scope, active area, selected item, and revisions;
- snapshot, base version, loading, busy, server-draft, error, and exit state;
- initial load, reload, draft save, preview, publish, and rollback commands;
- the single mutation gateway that replaces snapshot collections and marks a
  local unsaved edit;
- navigation to the existing client-source and pipeline editors;
- user-facing API error translation and success notifications.

Create three semantic `part` files:

1. `crm_configuration_workspace_shell.dart` — toolbar, responsive layout,
   navigation, generic list/detail framing, history view, impact preview, and
   reason dialog.
2. `crm_configuration_workspace_schema.dart` — field, category, option-set,
   settings presentation and their editor dialogs.
3. `crm_configuration_workspace_commerce.dart` — lesson settlement and teacher
   compensation presentation, reordering, preview, and editor dialog.

Create one imported internal library:

- `crm_configuration_snapshot.dart` — deep copy, legacy-field and inline-option
  migrations, stable option keys, deterministic collection reorder/upsert,
  catalog ordering, and money-value conversion.

The shell, schema, and commerce files may define private `StatelessWidget` or
`StatefulWidget` components. They must not read Riverpod providers, call
`ClientFormsApi`, navigate through global infrastructure, or own the canonical
configuration snapshot. They report user intent through callbacks.

The snapshot library is Flutter-independent. Local editor drafts that own
Flutter controllers stay beside their editor instead. Snapshot functions accept
and return copied maps/lists and must not mutate caller-owned inputs unless the
contract explicitly names in-place normalization during initial load. Its
symbols are accessible to its direct unit test but are not re-exported from the
feature barrel.

## State and mutation contract

There are two deliberately different dirty states:

- `_dirty` means the loaded server configuration is a draft that can be
  published. Saving a draft therefore leaves `_dirty == true`.
- `DirtyFormExitController` means the local widget contains edits not yet saved
  to the server. Saving a draft marks this controller clean.

Every local schema or commerce mutation must pass through the coordinator's
single replacement callback. That callback copies the affected collection,
updates `_snapshot`, sets `_dirty = true`, and calls
`_exitController.markDirty()`.

Changing branch scope reloads both draft and revisions and clears selection.
Initial normalization may mark local exit state dirty only when a legacy
migration actually changes the school snapshot. Normal loads mark it clean.

The publish sequence remains:

1. Require a snapshot and `config.crm.publish`.
2. Preview using the current branch, base version, and complete snapshot.
3. Collect a non-empty reason only when preview is valid.
4. Publish with the same branch, base version, reason, and snapshot.
5. Reload draft and revision history from the server.

Rollback continues publishing a new revision using `expectedVersion` and
`targetVersion`; it never rewrites or deletes history.

## Permission and scope invariants

- The route performs no configuration request without `config.crm.read`.
- `config.crm.edit` controls draft changes and saves.
- `config.crm.publish` controls preview, publication, and rollback.
- Managers automatically use an allowed branch, never see school scope, never
  publish, and never see commerce catalogs.
- Commerce catalogs remain visible only to Director/system_admin with read
  access and mutable only when both edit and publish are present.
- School-only structural operations and legacy migrations remain guarded by
  `branchId == null`.
- Backend authorization remains authoritative; hidden or disabled UI cannot
  create an alternate request path.

## Test design

Preserve the existing CRM configuration widget suite as the principal
characterization boundary. It already covers initial publication, source
editing, impact preview, schema types and placement, commerce independence,
dirty back navigation, rollback, manager scope, forbidden roles, legacy field
merge, inline-option migration, stable option keys, reorder, and archive rules.

Before moving pure transformations, add direct tests for:

- deep-copy isolation;
- idempotent legacy field and inline option migration;
- lossless merge and incompatible legacy type failure;
- stable option-key preservation and collision suffixing;
- deterministic category/catalog reorder and hundredths conversion.

Existing public widget tests must continue importing only
`crm_configuration_workspace.dart`. Existing keys and Russian labels remain
unchanged so the cut cannot silently replace behavior with a new test-only
contract. The device configuration test remains a final smoke gate.

## Implementation sequence

1. Add failing or characterization-level unit tests for snapshot operations.
2. Extract snapshot transformations and editor dialogs without changing the
   coordinator or public imports.
3. Extract schema and commerce widgets behind immutable inputs and callbacks.
4. Extract the shell and publishing/reason dialogs; reduce the coordinator to
   lifecycle, access, state transitions, API commands, and intent handling.
5. Run focused and full verification, update the RepoWise index, compare
   RepoWise/Sentrux metrics, and commit each logical cut separately.

After each structural step, run the focused CRM configuration widget/unit tests
and a Sentrux rescan. A failed behavioral gate is fixed before the next
extraction begins.

## Acceptance

- Public route, helper, widget class, barrel export, API requests, response
  handling, labels, keys, and responsive behavior remain compatible.
- `_CrmConfigurationWorkspaceState` has no god-class finding and is at most 600
  NLOC; its methods are coordination and intent handlers rather than large UI
  builders.
- No method introduced or retained by the cut exceeds CCN 10.
- Extracted presentation widgets do not read providers or call the API.
- Snapshot transformation tests and the existing CRM configuration widget suite
  pass; final Flutter analysis and the relevant device smoke test pass.
- Sentrux quality is at least 0.4976, acyclicity remains 1.0, depth is no higher
  than 13, and both architectural rules pass.
- RepoWise is indexed at implementation HEAD. Changed-file health reports no
  critical god class, and change-risk inspection finds no missing production
  caller or untested mutation path.
- The exact metric improvement is measured after the split rather than inferred
  from lower physical file length.

## Rollback

Revert the shell extraction, then schema/commerce extraction, then snapshot
extraction in reverse commit order. Because the public API, server contract,
database, and production data do not change, rollback requires no migration or
data action.
