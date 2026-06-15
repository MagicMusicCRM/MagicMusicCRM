# Flutter Integration Smoke

This smoke test covers app launch, the auth gate and the account deletion form
without requiring staging credentials, external secrets or real user data.

## Scope

- Starts `MagicMusicApp` with an in-memory token store.
- Replaces notification setup with a no-op service so Firebase/FCM permissions
  do not make the test flaky.
- Verifies that the app reaches the Russian login gate.
- Verifies the login form and local required-field validation.
- Starts an authenticated account deletion route with fake release-gate data.
- Verifies that deletion submission is disabled until the user confirms the
  acknowledgement.
- Verifies deletion request submission and the Russian pending-status screen.

## Command

```powershell
flutter test integration_test\app_launch_smoke_test.dart
```

For device-backed runs, pass the target device explicitly:

```powershell
flutter test integration_test\app_launch_smoke_test.dart -d windows
flutter test integration_test\app_launch_smoke_test.dart -d <android-device-id>
```

## Boundaries

This does not replace branded native-launch screenshot evidence or the real
Android staging smoke for login, private file upload/download, account deletion
against the real backend or imported CRM workflows. Those still require a stable
device, staging credentials and cleanup evidence.
