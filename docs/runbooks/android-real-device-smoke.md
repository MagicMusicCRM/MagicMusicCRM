# Android Real-Device Staging Smoke

Use this runbook when a stable Android device is connected and staging smoke can
mutate disposable test data on `https://api.magicmusiccrm.ru/api`.

## Preconditions

- `flutter devices` shows a physical Android target.
- Use only disposable staging smoke accounts and CRM records.
- Do not put HolliHop keys, DB URLs, passwords or refresh tokens in this file,
  Linear, screenshots or logs.
- Build from the current working tree:

```powershell
flutter build apk --debug --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api
```

## Automated Helper

Run the helper from the repository root:

```powershell
.\scripts\android_real_device_smoke.ps1 -RunIntegrationSmoke
```

Useful options:

```powershell
.\scripts\android_real_device_smoke.ps1 -DeviceId <android-device-id>
.\scripts\android_real_device_smoke.ps1 -SkipBuild -RunIntegrationSmoke
.\scripts\android_real_device_smoke.ps1 -CheckOnly
```

The helper refuses non-HTTPS API URLs, does not accept HolliHop/DB secrets,
selects a physical Android device, writes evidence under
`.supergoal/hollihop-crm-import-adaptation-loading-ux-Guw3IO/evidence`, builds
and installs the debug APK, optionally runs `integration_test`, launches the app
through `adb` when available and fails if logcat contains `FATAL EXCEPTION`,
`FlutterError` or `Dart Error`.

## Install And Log Capture

```powershell
flutter devices
flutter install -d <android-device-id> --use-application-binary build/app/outputs/flutter-apk/app-debug.apk
flutter logs -d <android-device-id> > .supergoal/hollihop-crm-import-adaptation-loading-ux-Guw3IO/evidence/android-real-device-flutter-logs.txt
```

If `flutter logs` is not enough for native crashes, use the Android SDK `adb`
from the path reported by `flutter doctor -v` and capture `logcat -d`.

## Required UI Smoke

- Cold start: native launch screen is cream/gold, no black pre-frame screen.
- Auth: login or signup with a disposable account.
- Onboarding/legal: complete required gates and confirm Russian copy is visible.
- Dashboard/messenger: open `Администрация`, send a unique message and confirm
  it appears without Flutter/Dart/Fatal errors in logs.
- Private files: attach a small disposable file in a chat, reopen/download it and
  confirm the UI does not expose public Supabase URLs.
- Account deletion: from profile, open `Удалить аккаунт`, enter a disposable
  reason, check the acknowledgement, submit and confirm `Запрос принят`.
- CRM manager/admin slice, when using a manager/admin smoke account:
  - student card metrics and invitation action are visible;
  - lead attach-to-existing-student flow is visible for a safe duplicate;
  - lead saved presets and automatic loading on scroll work;
  - staff detail edit/link navigation opens;
  - schedule availability/conflict labels render;
  - task timeline/add-history and reassignment actions render;
  - debtor drilldown and `Добавить оплату` render.

## Evidence

Record these in the Phase 11 evidence note:

- Device model, Android version and device id.
- APK SHA-256.
- Test account email hash or disposable identifier, not the raw password.
- Unique chat message text and backend/API confirmation id when available.
- Screenshots for cold start, files and account deletion status.
- Log review result: no `FATAL EXCEPTION`, `FlutterError` or `Dart Error`.
- Cleanup result for smoke users, uploaded files, deletion request and CRM test
  records.

## Cleanup

- Use admin UI or backend cleanup scripts for disposable smoke records only.
- Confirm no smoke users, messages, uploaded files or deletion requests are left
  unless the evidence explicitly says they are intentionally retained.
- Do not run production cutover, DB import `apply` or destructive cleanup from
  this runbook.
