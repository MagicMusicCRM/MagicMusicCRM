# 09_S7_RELEASE_EVIDENCE - MagicMusicCRM v1.1.6

**Date**: 2026-06-12
**Scope**: S7 pre-release security and Google Play AAB gate
**Release**: `v1.1.6+116`
**AAB**: `build/app/outputs/bundle/release/app-release.aab`

## Result

S7 pre-release gate is accepted for the `v1.1.6` Google Play bundle.

Full production launch/cutover remains gated by operational items that cannot be completed from the local workspace alone:

- rotate previously exposed Supabase/service credentials and server passwords;
- point production `api.magic-music.org` to the final v3 production backend when ready;
- rerun live DB-backed HolliHop `-UseLiveApi` dry-run after the archive DB-backed gate and live validate-only inventory;
- smoke staging invitation email delivery through the configured email provider;
- run external history-aware secrets, SAST and container scans;
- run final production cutover rehearsal and production smoke on the final server;
- complete user-owned S6 Android UI checks for file attachment/download and account deletion.

## Post-Gate HolliHop Rehearsal Update - 2026-06-15

- Guarded helper `scripts/hollihop_staging_dry_run.ps1` now safely loads ignored local env files, keeps process env values higher priority, forces `dry_run`, requires backup evidence and hides DB/HolliHop secret values.
- Fresh encrypted staging backup evidence: `.supergoal/hollihop-crm-import-adaptation-loading-ux-Guw3IO/evidence/magicmusiccrm-staging-20260615T131610Z.tgz.enc` plus `.sha256`.
- Archive DB-backed staging dry-run passed: report `hollihop-import-2026-06-15T13-40-42-091Z.json`, batch `3c4fc480-74a7-4801-a0e2-45c26972004a`, warnings `tasks_source_missing` and `timeline_sources_missing`, secret grep clean.
- Live HolliHop validate-only inventory passed without DB writes: `1,025` students, `1,944` leads, `2,264` education units, `1,211` memberships and `3,166` payments.
- Remaining HolliHop launch blocker: live DB-backed `-UseLiveApi` dry-run still fails at the connection/client stage before report generation.

## Build Artifact

| Field | Value |
|---|---|
| Version name | `1.1.6` |
| Version code | `116` |
| API target | `https://api.magic-music.org/api` |
| AAB path | `build/app/outputs/bundle/release/app-release.aab` |
| AAB size | `50,324,572` bytes |
| SHA-256 | `D6E0BE113070FC62F41171F403351702A39ABE1C5291A0882247D04106C5DF5D` |
| Signing | Release signing configured through `android/key.properties`; AAB includes `META-INF/UPLOAD.SF`, `META-INF/UPLOAD.RSA`, `META-INF/MANIFEST.MF` |
| Signer expiry | `2053-10-15` |

Build command:

```bash
flutter build appbundle --release --build-name=1.1.6 --build-number=116 --dart-define=MAGIC_API_BASE_URL=https://api.magic-music.org/api
```

## Verification

| Gate | Result |
|---|---|
| Backend typecheck | Passed: `npm run typecheck` |
| Backend tests | Passed: `28` suites, `123` tests |
| Backend build | Passed: `npm run build` |
| Backend dependency audit | Passed: `npm audit --audit-level=moderate`, `0` vulnerabilities |
| Flutter analyze | Passed: `No issues found` |
| Flutter tests | Passed: `52` tests |
| Staging health | Passed: `https://api.phantom-net.ru/api/health` returned `200` |
| Staging realtime smoke | Passed: `npm run smoke:realtime`, message/event match |
| Security gate | Passed with warnings: `7` pass, `4` warn, `0` fail |
| AAB build | Passed: `app-release.aab` built |
| AAB signing presence | Passed: signed AAB entries present and signer certificate readable |

## Security Gate Warnings

The repeatable local security gate did not find a blocking failure. It kept four warnings because external production-grade tools are not available in the local Windows environment:

- `gitleaks` unavailable locally: history-aware secret scan remains a production gate.
- `semgrep` unavailable locally: external SAST remains a production gate.
- `trivy` unavailable locally: container/dependency image scan remains a production gate.
- Docker daemon unreachable: container image scan remains pending.

These warnings do not block the local AAB build, but they remain required before final production DNS cutover.

## Dependency Backlog

`flutter pub outdated` reports constrained/outdated packages and one discontinued transitive package:

- transitive `js 0.6.7` is discontinued;
- several Firebase, Google Sign-In, Syncfusion, file picker, audio and secure-storage packages have newer major versions.

No dependency vulnerability was reported by `npm audit` for the backend. Flutter package updates are tracked as release-hardening backlog, not as a blocker for this AAB.

## Acceptance Notes

- S6 Android UI file/deletion tests are explicitly delegated to the user.
- T7.3/T7.4 production cutover tasks remain deferred until the final production server and DNS are available.
- The AAB is suitable for Google Play upload as a signed `v1.1.6+116` artifact, assuming the production API domain is ready when users receive the release.
