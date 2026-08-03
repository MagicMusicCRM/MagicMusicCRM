# V6-103 — Safe Workspace Restore & Logout Reset

**Result:** PASS  
**Scope:** account-scoped Flutter workspace persistence.

## Invariants verified

- Secure key includes schema version and encoded account identity.
- Persisted content contains typed route/view state only; dirty drafts/domain payloads are excluded.
- Restore validates schema, account, tab count/IDs, typed link support and current capability policy through `EntityRouteRegistry`.
- Corrupt, unsupported or forbidden snapshots use a safe fallback.
- Restart restores permitted tab order, active tab and view state.
- Global logout marks every attached window logged out and removes the account cache.
- Auth session changes invoke the same workspace logout coordinator before tokens/realtime change.
- Account/role change clears privileged cached tabs before the replacement workspace restores; only a safe permitted fallback may be persisted again.

## Verification

```powershell
flutter test `
  test/features/v6/production_workspace_mount_test.dart `
  test/features/v4/workspace_persistence_logout_test.dart `
  test/features/v4/desktop_workspace_controller_test.dart
flutter analyze
```

Result: 12/12 targeted tests passed; analyze clean. Scenarios cover restart, schema/corrupt snapshot, forbidden route, cross-account namespace, role downgrade, two-window logout and post-logout late navigation denial. Server diff is empty.

