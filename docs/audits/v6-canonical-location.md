# V6-101 — Canonical App Location

**Result:** PASS  
**Scope:** Flutter navigation metadata only; server diff empty.

## Delivered contract

- `EntityRouteRegistry` remains the single policy/target registry and now returns `CanonicalAppLocation` for resolved links.
- Canonical metadata contains stable route name, typed `EntityLink`, URI, actor-safe generic title, declared capabilities, surface kind, typed breadcrumb ancestor and view-state schema version.
- `resolveLocation` converts supported direct GoRouter URLs/query links back into typed `EntityLink` and then uses the same registry policy.
- Forbidden or unsupported direct links fail closed before canonical metadata is exposed.
- `ContextViewState` is versioned and rejects unknown persisted schemas.

## Verification

```powershell
flutter test `
  test/features/v6/canonical_app_location_test.dart `
  test/features/v4/entity_link_registry_test.dart `
  test/features/v4/context_transition_matrix_test.dart `
  test/features/v4/mobile_context_navigation_test.dart `
  test/features/v4/workspace_persistence_logout_test.dart
flutter analyze
```

Result: 20/20 targeted tests passed; analyze clean. The source URL and in-app typed link serialize to identical canonical metadata. No second router/registry or dependency was introduced.

