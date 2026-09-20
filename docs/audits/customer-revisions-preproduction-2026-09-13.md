# Customer revisions: local pre-production verification

Historical preproduction evidence. **Superseded by the successful 1.5.42+222
production release on 2026-09-16**; see [release audit](release-222-production.md).
The statuses below describe their original verification stages, not current
production readiness. The final release reused applicable unchanged-source tests,
rebuilt/verified artifacts, checked fresh backups and verified production after deploy.

## Final client packaging and network blocker, 2026-09-16

The owner explicitly authorized deployment. Fresh 1.5.42+222 Windows Release,
Setup, ZIP, signed Android APK and AAB builds passed. Evidence and artifact hashes:
`dist/release222-final/artifact-manifest.json`. Windows ZIP matches all 31 Release
files; APK v2 signature and AAB jarsigner verification pass, both certificates
match production. Windows Setup remains unsigned. APK/AAB embedded release history
contains build 222. The 2137-file frozen source fingerprint is
`7d917924a5c8c286c9ce4f40b6c1c67161aa7738ca59e052e05be5ae9ab0f03c`.
These are packaging checks, not a new full functional run of the signed binaries.

Deployment is blocked: production SSH closes before key exchange and HTTPS
readiness fails before TLS establishment in both curl and Node. DNS resolves the
expected IP; GitHub HTTPS works and the local SSH key parses. The cause remains
unknown; the owner was asked about VPN/connectivity. No fresh backup, production
write, upload, cutover or channel publication occurred. Final server release
identity is also pending; the verified server still has its local candidate tag.
Resume with fresh remote preflight and backup/restore verification, compatible
recovery deployment, post-deploy reconciliation, then client publication.

## Full-compatibility preparation, 2026-09-16

The owner selected a compatible recovery server rather than accepting degraded
teacher-report filtering. This supersedes the old recovery limitation below.

- Recovery image: `magicmusiccrm-server:221-recovery-0156-c59fd72bb33e`, ID
  `sha256:bd341e0bb67564d3cb4c466addb496ca517570628c0972a2e51cc6a8396e919d`.
  Allowlist and source hashes: `dist/recovery-images/63c58ddecf98431c9918c95517fad567/manifest.json`.
  Compiled DTO/filter contract rejected the old recovery and passed the new image.
- Image switch: `dist/http-journeys/a31426557ce8489287b37f4138ceb4b5/`,
  **27 PASS, 0 FAIL**, 58 built-in HTTP requests, zero server errors. Real completion
  worker generated trial/standard facts; filtered totals (0/700 RUB), exact lesson
  IDs and normalized XLSX worksheets matched before/after switching. All seven
  lesson/history/fact table fingerprints stayed unchanged on startup/report reads;
  manual-pay preservation, rejected arbitrary rates and idempotent reschedule passed.
- Encrypted restore/migration/reconciliation: `dist/release-prep-full-recovery-drill/`
  PASS. This used the September 12 backup, not a new pre-deployment backup.
  `dist/release-prep-full-recovery-health.log`: invalid flags fail closed, healthy
  readiness and intentionally degraded HTTP 503 all PASS; temporary DBs/containers
  removed. Shared backported financial code is not an independent fallback for a
  defect in that same code.
- Two client changes: removed the second Android permission request; exempted only
  login from ambiguous-business-write error text while retaining that warning for
  lesson/payment writes. Red run: 10 PASS/4 FAIL; fixed focused run: 14 PASS/0 FAIL,
  `dist/release-prep-regression-before.log` and `dist/release-prep-regression-after.log`.
  Permission test is structural, not OS-runtime evidence. The September 13 frozen
  client artifacts are now stale and must be rebuilt/reverified.

Intermediate expanded-switch failures were test-fixture defects, not accepted
passes: missing manual-change reason (`a3f9fc6efbe34ac5aef569f0424706bf`), using a
manual review endpoint for normal completion (`3ae175b0c3dc49998fa7a6d1b1eeb9ff`),
and operator-created explicit zero-rate snapshots (`7e25f244e31d460ab569f5f0c8cbe05e`).
Final fixture authenticates the ordinary administrator before creation, asserts
the 700 RUB stored snapshot, and completes via the real worker. Production
validation/RBAC/calculation were not weakened to accommodate these fixtures.

Final full client run: `dist/release-prep-flutter.jsonl`, **1797 PASS, 0 FAIL**,
four intentional updater skips, exit 0 (320 seconds). Existing separate updater
PASS evidence remains applicable: its implementation has not changed. Focused
Dart analysis: `dist/release-prep-analysis.log`, no issues. Four Node runner guard
tests passed. `git diff --check` passed; RepoWise index update completed.

Android runtime verification used the ordinary `lib/main.dart` entrypoint, not
the integration harness, on the dedicated API35 emulator. Debug x86_64 build:
`dist/release-prep-android-main-build.log`; APK SHA256
`230c86587a5d676075d1c5ddfa12308d666f476288e38b091c3f0deeb90f8d39`.
Compile overrides: `MAGIC_API_BASE_URL=http://127.0.0.1:9/api` and isolated
`MAGIC_PROFILE=qa-release-prep-20260916`. External networking was disabled.
The initial Android System UI ANR dialog recovered after choosing Wait; this was
not attributed to the CRM. After denying the single notification permission
prompt, the normal login screen remained usable and no second prompt appeared
during the remaining session. Permission stayed denied. Offline sign-in displayed
`Не удалось подключиться к серверу.` without the misleading saved-action warning.
Evidence: `dist/release-prep-android-prompt-2.xml`,
`dist/release-prep-android-after-denial.xml`,
`dist/release-prep-android-offline-login.xml` and `.png` (visually inspected).
`dist/release-prep-android-crash.log` is empty; Flutter log shows the expected
offline FCM authentication/token failure. Push delivery was not tested.

At that stage Android login/navigation, mobile move-save and Windows installation
acceptance were still pending. The later Android section below records the completed
scoped checks and the owner's Windows UAT waiver. Final signed artifacts/source
identity and a fresh backup remain necessary. Neither this Debug APK nor the stale
September 13 frozen artifacts are the final release candidate.

## Candidate identity

### Android ordinary-entrypoint acceptance, 2026-09-16

Evidence: `dist/http-journeys/cbb2678c0b4e483dbd86ef5f6c7940f5/`.
The owner waived Windows Sandbox installation/upgrade UAT, but explicitly required
these Android checks. Both were observed through ADB UI interaction on the dedicated
API35 emulator, with external networking disabled and loopback `adb reverse`:

1. Entered administrator credentials in the normal login form, completed first-run
   profile/consent screens for the synthetic local account, opened chat, clients/
   students, tasks and schedule. No injected session, in-memory auth or mounted
   substitute widget was used. Force-stop/relaunch restored the authenticated session.
2. Opened the trial lesson from the actual daily calendar, used its move action,
   selected Room 1 and 12:30 through the editor, entered a change reason, calculated
   and confirmed. Exact pre/post-preview API responses match: preview did not write.
   After force-stop/relaunch, navigated back to January 12 and reopened the lesson:
   Room 1, 12:30–13:15. Real API response confirms one scheduled successor, 45 minutes,
   free client charge and trial teacher compensation rule preserved.

Files `10-workspace.xml`, `12-students.xml`, `13-tasks.xml`, `before-preview.json`,
`after-preview.json`, `35-relaunch.xml`, `40-lesson-reopened.xml`/`.png` and
`after-reopen-server.json` substantiate the steps; final screenshot visually inspected.
The crash log is empty. Flutter log contains only expected offline FCM token failures
among error matches; push delivery was not validated. SDK API35, x86_64 Debug,
ordinary `lib/main.dart`, isolated storage namespace and local API compile override.
APK SHA256: `01dd4614f3fd19bb2e7438e9e396d8f606c0f2f104719c4e5c1a0228a9053575`.
Runtime client/backend source was not changed by this acceptance work.

The combined runner retains **22 PASS, 1 FAIL**, 44 built-in HTTP requests, zero
built-in HTTP 5xx. Its new post-UI verifier erroneously read snake_case fields from
the camelCase HTTP DTO. This was a verification-script defect, not an app failure.
After correcting the verifier, three focused Node tests passed, including negative
room/duration/payment cases; revalidation of the captured real response and all four
observed UI steps passed in `android-main-revalidation.json`. This is a scoped
revalidation, **not a second full live gate**, and the original FAIL is retained.
An initial ad-hoc PowerShell timestamp assertion also mixed UTC/local DateTime;
explicit UTC normalization confirmed `2027-01-12T09:30:00Z` (12:30 Moscow).

Remaining release work: fresh signed client artifacts and source identity, fresh
pre-deploy backup, controlled deployment and post-deploy reconciliation. This test
APK must not be published. Windows installation/upgrade remains owner-waived, not PASS.

Base revision: `25b9a9e6d33d44a9579af394efc10009a845836a` plus the local
customer-revision working-tree changes. The base revision alone does not identify
this candidate. `.claude/CLAUDE.md` and unrelated `outputs/` files are excluded.

Local server image: `magicmusiccrm-server:customer-revisions-local-20260913`.
Image ID: `sha256:87449ffce05ef9808a2de160c0e1506d4befe66606a9f02d0bb201455bc4eccb`.
Its revision label identifies the base commit, not a clean release commit;
`com.magicmusiccrm.dirty=true` and `com.magicmusiccrm.source-fingerprint` identify
the tested local state. This image has not been published.

## Fixes made during verification

1. Preserved the legacy trial marker on old-client payloads without reinterpreting
   historical payment decisions. New `trial_lesson` decisions remain free.
2. Moved manual trial-pay preservation into the existing reschedule financial
   helper, keeping the transition owner within its architectural boundary.
3. Kept provider-backed global search in the workspace host, not its passive view.
4. Bounded the new filter dropdown; extracted the teacher compensation filters
   without changing report calculations. Corrected the legacy-catalog trial-to-free
   selection branch so the draft does not retain an obsolete trial marker.
5. Updated obsolete checkbox/catalog expectations and provided valid access
   snapshots in existing form mocks. No validation or authorization gate was removed.

## Verification evidence

- Full backend: `server/coverage/test-runs/9949d22a6d2baff5/` passed 4135/4136
  cases; the sole failure was the five-second PGlite integration-case timeout.
  The case passed unchanged in `1ef9e9efc7b696b6` (7304 ms, with synchronous WASM
  startup). Its explicit integration timeout is now 30 seconds; assertions are
  unchanged. Final full rerun: `server/coverage/test-runs/a22d07ea26f70653/`:
  **317 suites, 4136 tests passed, zero skips**, with verified unchanged source
  fingerprint `264cf02b20e34db918dc0cfe2541c4b0d8d08d564f1f41c440e1fd59e1bda748`.
- Full Flutter: `dist/customer-revision-flutter-release.jsonl`: **1790 passed**,
  four intentional updater-only skips, zero failures. The four updater cases
  passed in the final dedicated run `dist/customer-revision-updater-final.jsonl`
  (four passed, zero skips); per-mode evidence is in
  `dist/customer-revision-updater-final/`.
  Two earlier combined runs stopped progressing in the compiler and were
  interrupted; neither is PASS evidence. The completed run used concurrency 4
  and did not launch the updater's external fixture processes alongside widgets.
- Native Windows trial journey: `dist/http-journeys/bc48206104a34787811a745725892932/`.
  Six UI checkpoints passed: default trial, administrator manual teacher pay,
  six-room daily drag with unchanged duration and preserved manual pay, client
  settlement filter, teacher search/card, administrator search/card. Built-in HTTP
  journeys: 23 checks, 44 requests, zero server errors; native UI: 71 requests,
  zero failed requests. Source fingerprint:
  `d65990ad03b2f549594da1e3caa7b6ab204a7e712c2dcb64e06c718dab99625f`. Product surfaces
  use real local HTTP/PostgreSQL; the CRM invalidation stream is disabled.
- Earlier employee journey: `dist/http-journeys/f110730ecad043128c12cc21a39685d7/`.
  Booking/completion/edit/cancellation/refund, retry, concurrency and synthetic
  backup restore passed. This preceded the final compatibility/UI fixes and is
  supporting evidence, not a final-candidate whole-app PASS.
- Flutter analysis of `lib` and the new native test, backend typecheck and
  expense/payment OpenAPI drift checks passed. Existing
  strict security gate: 11 pass, zero warnings/failures (including npm audit).
  This gate checks scanner availability; it is not an independent penetration test.
- Local server image gate passed: invalid configuration fails closed, healthy
  readiness/healthcheck, and degraded readiness returns HTTP 503. Disposable image
  containers/databases were removed and their absence checked.

Deploy, deploy-database, backup, backup-compatibility static contracts and the
isolated deploy behavior harness passed. They do not override the failed real
rollback drill below. The image checks preceded only a test-timeout edit, not a
subsequent backend runtime change.

## Confirmed release blocker: rollback compatibility

The encrypted production backup from 2026-09-12 was verified and restored into
an isolated Docker database. Candidate migration `0156_trial_lesson_catalog` and
V7 reconciliation passed. The drill then **failed** when the unmodified production
221 image attempted its normal migrator against the candidate schema.

Evidence: `dist/customer-revisions-backup-drill/result.json` and `restore.log`.
Backup: `magicmusiccrm-staging-20260912T192858Z.tgz.enc`;
SHA-256: `fecaaf9c4695cbd51c79bd290748ddf8c60f7ea69c787378fb74d5bda1a459d9`.

The verified migrator rejects applied migrations missing from its image.
Image 221 does not contain migration 0156. Do not bypass this check, delete its
migration record, run a destructive down migration, or restore yesterday's database
over transactions accepted after deployment. A schema-only migration-file bridge
would not by itself prove safe handling of new trial plans/manual teacher pay.

Before release, prepare and test a compatible recovery image against both the
restored database and newly created trial financial history, or explicitly agree
an alternative recovery strategy. The existing unmodified 221 image is not an
approved rollback target for this candidate.

## Local client build checks

### Recovery preparation follow-up (2026-09-13)

Local experimental recovery image built from the production 221 source plus an
explicit compatibility allowlist (nine source files and migration 0156 up/down):
`magicmusiccrm-server:221-recovery-0156-b8c049ee2b8c`, image ID
`sha256:95447d6142e57113666c808938b7a7c5a58fec83c666ff85344e7dee24ed89a3`.
Reproducible export/build script: `scripts/build-customer-recovery-image.ps1`.
The working tree is not switched. Exact backport hashes and base revision:
`dist/recovery-images/0cfe0751eb43443fa76f337add3bf67f/manifest.json`.

The encrypted production-copy migration/reconciliation/rollback drill now
**passes** with that exact image:
`dist/customer-revisions-compatible-recovery-drill/result.json` and `restore.log`.
The migrator was not weakened and no migration record/history was removed.
This resolves the demonstrated missing-migration failure for the experimental
image, but does **not** yet approve it as a complete recovery target.

Limitations: financial safeguards intentionally share the candidate's fixes;
this image is not an independent remedy for a defect in those fixes. Schedule
query compatibility is included because the current UI sends branch scope in
ordinary schedule requests. The new teacher compensation report filter is not
backported; its query parameter is absent from the baseline DTO. That degraded
recovery behavior has not been accepted by the owner or exercised over HTTP.

The HTTP journey harness can now launch exact local Docker image IDs, binding
HTTP to loopback and allowing only a generated local test database. Its two
environment-safety tests passed. A candidate-to-recovery switch check was added
for persisted manual trial pay, immutable history at startup, forbidden admin
rate overrides, pure reschedule preview and idempotent commit. They initially
had no PASS evidence; the completed rerun is recorded below.

Attempt `dist/http-journeys/d82d8546c2da4aa58b821e284bcb42dd/` passed 22 built-in
checks / 44 HTTP requests / zero HTTP 5xx on the actual candidate image, but the
native UI build failed before running. Therefore manual-pay preconditions and
the recovery switch were not reached; the run correctly reports failure.
Verbose diagnosis `dist/recovery-windows-build-diagnostic.log` identifies
`FileSystemException: writeFrom failed ... app.dill`, OS errno 112 (disk full).
C: had approximately 0.03 GiB free. Do not treat the earlier native UI PASS as
evidence for this unexecuted image-switch scenario.

The owner subsequently removed the regenerable `.dart_tool/flutter_build` cache;
28.86 GiB became available. The agent's deletion command had been blocked, and
the agent did not bypass that restriction. Source, backups and release packages
were not deleted.

The resumed exact-image run `9683eea74baf4e42aa4f9dc5a28d78bc` passed native UI
and startup-history checks but exposed a test-harness contract error: it copied
the persisted server-owned `teacherRateSnapshot` into a reschedule request.
The API correctly rejected it with HTTP 400. The harness now builds an explicit
client-input draft. Three focused harness tests pass; API validation and backend
runtime code were not changed.

Final run `dist/http-journeys/5787c34d58c944b58589925f62224754/`:
**26 checks passed, zero failed; 50 built-in HTTP requests, zero HTTP 5xx**.
The six native UI checkpoints passed on the exact candidate image (71 additional
native-client HTTP requests, none failed). Then the
actual compatible recovery image took over the same synthetic database and:

- preserved fingerprints of seven lesson/history/financial tables at startup;
- read the candidate-created trial and its saved manual standard teacher rule;
- rejected an administrator's arbitrary rate with HTTP 403 and no fact changes;
- rescheduled with an automatic client draft while retaining the manual teacher
  rule, amount field and credited duration, original lesson duration and free
  client charge; preview was non-mutating and replay appended no duplicate facts.

Exact candidate/recovery image IDs are recorded in `image-runtime.json`.
Final harness/source fingerprint:
`d4e96679b753b847c49262e21d1efe0c8825aae3c92666d8ad8c9ab05f485718`.
The original production-copy restore drill remains valid: image IDs are unchanged.
`dist/customer-recovery-image-gate.log` additionally records PASS for invalid
configuration rejection, live/ready/healthcheck, and degraded readiness HTTP 503.
The tests' disposable containers/databases were cleaned up; production untouched.

The experimental image is still not a full-feature rollback: its real compiled
teacher-report DTO was checked in a network-disabled container. The original
query validates; `compensationRuleKey` is rejected with HTTP 400. This check used
the actual ValidationPipe/DTO, not an authenticated HTTP report journey. Owner
acceptance of that degraded mode is outstanding. The image also shares the new
financial safeguards and therefore is not a fallback for defects in those same
safeguards. `repowise update --index-only` completed after cache removal.

Provisional build arguments: `--build-name=1.5.42 --build-number=222`,
`--dart-define=APP_BUILD_NUMBER=222`, and the existing production API base URL.
No client was installed or launched against production. The source version,
release-history assets and public update manifests were not changed: these are
local build checks, not ready-to-publish distribution packages.

Android initially failed because a native UI test left `integration_test` in the
generated Java plugin registrant while Release excluded that plugin. Running
`flutter pub get --offline` and the normal build dependency-generation step
removed the stale entry; `pubspec.lock` is unchanged. Do not manually patch the
generated registrant or run UI tests between that regeneration and packaging.

- APK Release built; `apksigner verify` passed, version `1.5.42` / code `222`.
  SHA-256: `c1dcbf32caa3e599a79f66ebb3d536b2e43313ab48c09db9b3ac7c0a20455fcb`.
- AAB Release built; `jarsigner -verify` passed.
  SHA-256: `03ec7397d59aab8c1c314f8ab0534532eaa475d29c5fbe4fd77a0c0935e5b0a1`.
- Both Android artifacts use the same certificate SHA-256 as production 221:
  `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
- Windows Release compilation passed with updater number `222`, verified in the
  generated build configuration. EXE SHA-256:
  `636264aae0e2f8100cb7a55cb51bfbdf6e71d03e19cc4dc608ee1eb67195f3a7`;
  Dart AOT `data/app.so` SHA-256:
  `d5711c7716401290c7b1078d4fda4ca4725d3b416d6de5baf3a0e4a6bda3a56c`.
  Windows Setup/ZIP packaging has not been performed.

Artifacts are under `build/app/outputs/` and `build/windows/x64/runner/Release/`;
they are generated local files, not committed release assets.

The Android SDK/font and JAR self-signed/stream-order warnings also appear in
the recorded 221 build/signature logs; they are not newly introduced here.
At 2026-09-13 21:47 Europe/Moscow, a read-only public production readiness probe
returned `status=ok`, migration `0155_schedule_plan_archive`. No production
write or deployment was performed.

## Remaining release work

1. Accept or revise the limited recovery strategy above; its database/image-switch
   rehearsals passed, but the teacher report filter limitation is not approved.
2. Complete Windows Setup install/upgrade UAT. Seven scoped authenticated Android
   emulator checks passed on 2026-09-15 (details and limitations below); the two
   offline-login/permission observations remain open and physical hardware remains
   untested. Freeze the publishable Git/server release
   identity; the local source snapshot below does not mean a commit/tag was made.
3. Only after separate deployment authorization: fresh backup, server-first rollout,
   client publication, readiness and same-cutoff financial reconciliation.

## Local 222 package candidate after metadata alignment

The earlier provisional build artifacts above are superseded by
`dist/customer-revisions-222/`. No public manifest/upload/deploy was performed.
`pubspec.yaml` version/MSIX version, `windows_installer.iss`, bundled release history
and the history test now consistently identify `1.5.42+222`. The five changelog
entries describe only implemented scope; no weekly drag or automatic paid teacher
conversion is claimed. Seven history/update-center tests passed:
`dist/customer-revisions-packaging/release-metadata-tests.log`.

Windows Release rebuilt (75.3 s), APK (76.0 s), AAB (7.2 s), and Setup compile all
passed. Final ZIP contains 31 files; every entry's SHA-256 matches the rebuilt
Release directory. Windows updater define `APP_BUILD_NUMBER=222`, EXE product
version, and bundled history were checked. The Windows EXE/AOT hashes remain
identical to the previously tested binaries: this stage changes release metadata
and the bundled history asset, not application business logic.

APK v2 verification and AAB JAR verification passed. Both certificates match
production 221 (`0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`).
APK reports package `magic.crm`, version code 222, version name 1.5.42. Bundled
history 222 was read directly from both archives. JAR trust-chain warnings remain;
verified signing continuity is not a claim of public CA trust. Setup is unsigned,
as is the recorded production 221 installer. No private signing material was read
or printed.

Final artifact SHA-256:

| Artifact | SHA-256 |
| --- | --- |
| Windows ZIP | `f3a5ee7566e20df2f6e4afd4255510c4fb9de521752a4948b2711eac17fb8ec7` |
| Windows Setup | `06d843222067ba1108a0ca7721757bf523d2e739296e4bc3ffca6efa65311e76` |
| Android APK | `92a73f6b7d75620f9ca9a96ea3ccc6fc33d1f9ade1613a28078e890d6e07b939` |
| Android AAB | `16e5d1bcb8562d65cf1541aa8f457e1176d54d58b35bcec2824abc59de0d4909` |

`artifact-manifest.json` records hashes, checks and limitations. A 2131-file source
snapshot and manifest preserve the scoped dirty candidate, excluding unrelated
`.claude/CLAUDE.md`, outputs and ignored secrets/dependencies. Source fingerprint:
`e1ef71b1b907e40a9df98ade0c56114ac005900ee26b7a2c85bd010c1948d52e`.
Snapshot ZIP SHA-256:
`7d02ca0b9359e7625cf58f93baad616e4f8874b9a8b86ebe5a33652973f7fc96`.
The source manifest was checked for unchanged file contents before archiving;
no commit, tag or push was made. Backend images remain the previously verified
exact IDs; backend source and dependency lockfiles were not changed in this stage.

`adb devices -l` returned an empty device list, recorded in
`dist/customer-revisions-packaging/android-devices.txt`. No Android installation
or physical-device test was performed. The existing smoke helper defaults to
production and was deliberately not executed; device testing must use an isolated
fixture and avoid overwriting an existing installation without approval.
Windows Setup was compiled, not installed on a clean OS. These are outstanding
checks, not silently waived gates.

## Android emulator first pass, 2026-09-15

Owner decision: USB/physical device unavailable; use an emulator. A separate AVD
`MagicMusicCRM_QA222_20260915` was created from the already installed Android 15
(API 35) Google APIs x86_64 image, Pixel 6 profile, 1080x2400 at density 420.
WHPX reported installed and usable. The existing `MagicMusicCRM_API35` AVD was
not modified. First boot completed after Android's initial dex compilation;
an installation attempt before package services were ready failed, then the
same APK installed successfully after verified boot completion.

The exact signed candidate APK (SHA-256 `92a73f6b7d75620f9ca9a96ea3ccc6fc33d1f9ade1613a28078e890d6e07b939`)
reports installed version 1.5.42 / code 222. Wi-Fi and mobile data were disabled
before application launch; connectivity reported `Active default network: none`.
No production authentication or business request was performed.

Observed checks: cold launch, login render, declining notification permission,
required-field validation, text input with the Android keyboard, offline login
failure handling, and cold relaunch back to login. UI-derived coordinates were
used; screenshots and UI trees are under `dist/android-emulator-222/`.
The captured crash buffer was empty, and app-process logcat had no matches for
FATAL EXCEPTION, Unhandled Exception, FlutterError or Dart Error. This is scoped
evidence, not proof that all runtime failures are absent.

Two open observations, not yet root-cause fixes:

- After the first notification denial a second notification permission prompt
  appeared; its denial button changed to the deny-and-don't-ask-again form.
  Login became usable after declining both prompts.
- Offline login showed the generic ambiguous-command text saying an action may
  have been saved. The app remained usable, but that message is misleading for
  sign-in. See `offline-login-ui.xml` and `offline-login.png`.

This pass does not test authenticated lessons, teacher compensation, reporting,
notifications delivery, or API recovery on Android. Those require a local-fixture
Android test build/runner; the existing live harness reads desktop environment
variables and cannot simply be passed to an Android process unchanged. No
application source, backend, release artifact or frozen candidate was changed.

Weekly drag remains deliberately out of scope. RepoWise's change-risk response
scored HEAD, not this dirty working tree; its low score is not candidate evidence.
Live-source checks were used because semantic search/coverage evidence was absent.
`repowise update --index-only` completed after the source changes.

## Authenticated Android emulator checks, 2026-09-15

Final evidence: `dist/http-journeys/d5f0db6eda5a41158c47bb4d55daa731/`.
The gate returned **23 PASS, 0 FAIL**: 22 built-in server checks plus the Android
suite. Built-in requests: 44, zero HTTP 5xx. Separately, all **7 Android UI checks
passed**, with 50 real HTTP requests and no failed response. `android-flutter.log`
ends with `All tests passed!`; `android-crash.log` is empty.

Checked: trial settlement/free client/default trial teacher rule; administrator
selecting standard teacher pay and persistence after reopening; opening the lesson
from the six-room daily schedule without writing; the client settlement report
through its real `showLessonSettlementReport` mobile route; selecting the teacher
compensation filter; searching/opening the existing teacher and administrator cards.
The teacher report used a future period with no completed lessons: filter/query
and empty-state rendering passed, not populated payroll totals/export.

Source fingerprint: `a909d44e912cdd5551a31a160872b7001ea8cb89b8c7e4a9e5df3f0ef7f78a03`.
Server: exact local candidate image
`sha256:87449ffce05ef9808a2de160c0e1506d4befe66606a9f02d0bb201455bc4eccb`.
The runner used a fresh synthetic database on loopback port 55439, migration 0156,
and an ephemeral API port forwarded with adb reverse. External Android networking
was disabled (`Active default network: none`). No production request/deploy occurred.

A separate AVD `MagicMusicCRM_QA222_AUTH_20260915` retained the earlier exact-release
AVD untouched. Android 15/API35, x86_64, WHPX, GPU `host`, 1536 MB, two cores;
720x1600/density280 gives the same logical 411.43x914.29 viewport as the original
1080x2400/density420. Touch input and actual native layout were used, not a desktop
viewport or mouse-drag simulation.

Test tooling changes only: optional compile-time fixture input and native viewport
preservation in the shared harness; Android-specific route checks; a loopback-only
runner with dedicated-AVD guard and file-based results collection. Windows defaults
remain unchanged. A test-first runner guard and existing helper tests passed (4
tests); focused Dart analysis passed. RepoWise warned of 83 harness dependents and
high runner churn; its mock semantic index was supplemented by live-source reads.

The standard Flutter test connection repeatedly lost its VM/ADB transport before
tests started. Autonomous Debug APK execution removed that dependency. The first
software-GPU run then lost the emulator after three passing checks; GPU `host`
completed the run. Results are read from Android `code_cache/magic-evidence`, not
the initially assumed `cache` directory. Native instrumentation result delivery
warned that its plugin was absent; this run instead collected Dart test results,
per-step JSON, screenshots and logcat. It is not an Android instrumentation run.

The intermediate run `2e778dc47bee4bbfb3bf1b8ea61b95f2` found a 6.7px overflow when
the settlement dialog was mounted directly. Retesting through the actual mobile
modal route passed without changing application code. Earlier unsuccessful runs
remain as evidence; the interrupted `4a713cc5c1f14453b5c03809b3eb5a0c` also reports
a source change during its timeout, and is not a final candidate PASS.

Limits: authenticated checks use a local Debug test entrypoint, in-memory session
and workspace storage, real product widgets/services/RBAC, and disabled realtime
invalidation. This is not full navigation from the production login/home screen,
nor an authenticated run of the frozen signed APK. No Android drag/move-save,
physical-device, notification-delivery, recovery-switch or populated payroll/export
claim is made. Desktop daily drag retains its earlier separate evidence; weekly
drag remains out of scope. The two exact-release offline observations above are
not fixed by this work. Application/backend runtime source was not changed, and
the frozen candidate APK hash remains
`92a73f6b7d75620f9ca9a96ea3ccc6fc33d1f9ade1613a28078e890d6e07b939`.
