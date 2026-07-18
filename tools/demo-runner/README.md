# MagicMusicCRM demo runner

Project-local orchestrator for the four Android Studio AVDs used in the
MagicMusicCRM demo. It controls the devices through Appium/UiAutomator2; OBS is
deliberately outside this process.

## Fixed device contract

| Role | AVD | Serial | UiAutomator2 system port |
|---|---|---|---:|
| Client | `Client` | `emulator-5554` | 8211 |
| Teacher | `Teacher` | `emulator-5558` | 8212 |
| Admin | `Admin` | `emulator-5556` | 8213 |
| Manager | `Manager` | `emulator-5560` | 8214 |

The runner aborts before opening an Appium session if any serial, AVD name,
application version, boot state, or notification permission does not match.
This prevents an action intended for one role from reaching another device.

## Install and validate

```powershell
Set-Location D:\Projects\MagicMusicCRM\tools\demo-runner
npm ci
npm test
npm run doctor
npm run dry-run
```

`npm run doctor` resolves the local Android SDK and Android Studio JBR before
running the project-local UiAutomator2 diagnostics, so global `ANDROID_HOME`
and `JAVA_HOME` settings are not required.

`npm run dry-run` performs only ADB preflight and prints the selected plan. It
does not start Appium, request credentials, sign in, or execute UI actions.

`npm run dry-run:full` validates the concrete four-role business scenario in
`scenarios/full-demo.json`. `npm run demo:full` runs it. The scenario has 44
enabled steps: 43 use deterministic Appium actions and assertions; the only
operator checkpoint is the guarded external `fixture.reset-magic1` step. That
reset intentionally remains outside UI automation because it creates a backup,
requires explicit confirmation, and aborts on a fixture preflight blocker.
After the operator confirms the reset, the full cross-role UI path continues
without further manual placeholders.

The confirmed sale path keeps `magic1` as a lead through the trial lesson,
homework, submission, and feedback. The admin then taps **Выдать абонемент** in
the lead card once; that operation atomically creates the student,
subscription, and payment. The scenario deliberately contains no standalone
lead conversion, payment creation, or subscription assignment. A task is
verified in the admin's **Задачи** screen; task PUSH is not assumed because it
is not a confirmed backend contract.

The pinned toolchain is Appium `3.5.2`, UiAutomator2 `8.1.0`, and WebdriverIO
`9.29.1`. Appium discovers the driver from this package's `devDependencies`;
no user-global Appium installation is required.

## Runtime credentials

Credentials are requested only when a `login` action runs. They can be entered
interactively or supplied to the process:

```powershell
$env:DEMO_CLIENT_LOGIN='<runtime value>'
$env:DEMO_CLIENT_PASSWORD='<runtime value>'
$env:DEMO_TEACHER_LOGIN='<runtime value>'
$env:DEMO_TEACHER_PASSWORD='<runtime value>'
$env:DEMO_ADMIN_LOGIN='<runtime value>'
$env:DEMO_ADMIN_PASSWORD='<runtime value>'
$env:DEMO_MANAGER_LOGIN='<runtime value>'
$env:DEMO_MANAGER_PASSWORD='<runtime value>'
npm run demo
```

Do not put credential values in a scenario or a committed file. The runner:

- removes credential variables from the Appium child process environment;
- uses Appium/WebdriverIO error-only logging;
- redacts runtime values from errors and XML;
- clears failed login fields before taking failure artifacts;
- clears each login action's credential copies immediately after login;
- retains in-memory redaction guards until failure capture and shutdown finish;
- never writes credentials to checkpoints.

Clear the shell variables after a run if environment input was used.

## CLI

```text
npm run demo -- [--dry-run] [--resume]
                    [--from step.id] [--to step.id]
                    [--hold-ms 5000]
                    [--scenario scenarios/skeleton.json]
                    [--appium-url http://127.0.0.1:4723]
```

The default presentation hold is five seconds after every completed step.
`--from` and `--to` are inclusive. The runner refuses to reuse an unknown
process already listening on the selected Appium port. The default skeleton contains preflight and
the four login steps; it contains no business mutation.

## Scenario format

All UI selectors and choreography live in JSON, not in the runner. A step may
contain one `action` or an `actions` array, then `wait`, `assert`, and optional
`reconcile` conditions:

```json
{
  "id": "admin.open-client-card",
  "role": "admin",
  "description": "Открыть карточку demo-клиента",
  "actions": [
    {
      "type": "tap",
      "locator": {
        "using": "accessibility id",
        "value": "Клиенты"
      }
    },
    {
      "type": "tap",
      "locator": {
        "using": "android uiautomator",
        "value": "new UiSelector().descriptionContains(\"Demo Client\")"
      }
    }
  ],
  "wait": [
    {
      "type": "visible",
      "locator": {
        "using": "accessibility id",
        "value": "Карточка клиента"
      }
    }
  ],
  "assert": [
    { "type": "currentPackage", "value": "magic.crm" }
  ]
}
```

Supported locator strategies are `accessibility id`, `android uiautomator`,
`id`, and `xpath`. Prefer accessibility IDs. Use XPath only as a fallback.

Supported actions: `tap`, `tapIfVisible`, `setValue`, `scrollUntilVisible`,
`login`, `pause`, `back`, `pressKey`, `hideKeyboard`, `activateApp`, `home`,
`expandNotifications`, `collapseNotifications`, `restartApp`, `pushShadeTap`,
and the explicit `manual` placeholder. `scrollUntilVisible` uses the native
UiAutomator2 scroll gesture and defaults to the first Android `ScrollView`; a
different `containerLocator`, direction, percentage, or swipe limit may be set
per action.

Supported conditions: `visible`, `hidden`, `text`, `currentPackage`,
`notificationExists`, and the resume-only `manualConfirm` placeholder.

`manual`/`manualConfirm` are intentionally conspicuous operator boundaries.
In `full-demo.json` they are used only for the guarded `magic1` reset; all app
navigation, forms, messages, cross-role checks, lesson/subscription state, task
completion, chat archive, and five-second presentation holds are automated.

`setValue` can calculate Moscow dates at runtime, so a recorded demo is not
tied to the day on which the scenario was authored:

```json
{
  "type": "setValue",
  "locator": {
    "using": "android uiautomator",
    "value": "new UiSelector().className(\"android.widget.EditText\").instance(0)"
  },
  "valueFromClock": {
    "offsetDays": 2,
    "format": "dd.MM.yyyy",
    "timeZone": "Europe/Moscow"
  }
}
```

Use `"nextWeekday": 2` for the next Tuesday (ISO weekdays are `1..7`; the
current Tuesday advances by seven days). Clock-backed locators use the same
format with a `{clock}` placeholder, which lets the runner tap a materialized
date square without hard-coding the recording date:

```json
{
  "type": "tap",
  "locator": {
    "using": "android uiautomator",
    "value": "new UiSelector().description(\"{clock}\")",
    "valueFromClock": {
      "nextWeekday": 2,
      "format": "dd.MM",
      "timeZone": "Europe/Moscow"
    }
  }
}
```

Any step with `"mutating": true` must define `reconcile`. If execution stops
after such a step starts, `--resume` first checks whether the postcondition is
already true. Optional `resumeActions` can navigate back to the screen needed
for that check. A non-idempotent mutation is never repeated blindly.

## PUSH presentation helper

`pushShadeTap` backgrounds only the selected role's app, waits for a package
notification, expands Android SystemUI, holds the notification shade for five
seconds, taps the selected row, and verifies that `magic.crm` is foreground:

```json
{
  "type": "pushShadeTap",
  "role": "client",
  "marker": "Пробное занятие назначено",
  "locator": {
    "using": "android uiautomator",
    "value": "new UiSelector().textContains(\"Пробное занятие\")"
  },
  "shadeHoldMs": 5000,
  "expectedPackage": "magic.crm"
}
```

`marker` is mandatory; use a unique notification marker for the current demo run. A heads-up banner
is timing-dependent; the explicitly expanded shade is deterministic on video.

## Checkpoints and failures

`.state/checkpoint.json` is written atomically after verified steps. It stores
only scenario/run metadata, completed IDs, the in-progress ID, and explicitly
safe `checkpointData`. `--resume` requires the same scenario version.

On failure, screenshots and redacted Appium page sources for every connected
role are written under `.artifacts/`. Both runtime directories are ignored by
Git.
