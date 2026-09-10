# Production release 1.5.33+213 — 2026-09-09

Owner authorization: publish a new version including all previous fixes.
Guarded production cutover, Windows/Android downloads, both update manifests and
GitHub release v1.5.33 are published.

## Immutable identity and changes

- Commit/tag: `0cf7212052f5caea9fbad7c010fc096dc6f5bb86` / `v1.5.33`.
- Selected source SHA-256: `9d08f1457fb52fff7b52de5c91857c663106ce307ce6df9fce6e5c441d814c38`, 2179 files. Working source, isolated build snapshot and canonical Git blobs were compared.
- Image: `magicmusiccrm-server:1.5.33-213-final`, ID `sha256:2198bc6c93ea0029cd5ffd991dbe390abc8517114363f63376267c67d925a433`.
- Image archive SHA-256: `852128a712af1a3e9697744a9850f7152d7d64d517817549c04973f207d42dc2`.
- Schema remains `0154_retire_partial_miss`; no new migration.

Includes the schedule tail to next-day 01:00 at the existing scale, correct
midnight dates, one scrollbar per axis, roomier shared dialogs, first-error
focus/scroll and field validation, removal of the lesson self-link, and all
published 212 fixes. Release validation also corrected native date-picker button
metrics on phones and notification-preference spacing. Joi 18.2.8 and Multer 2.3.0
replace newly vulnerable dependency versions; NestJS stays on version 11.

The release commit was created using a temporary Git index with published 212 as
parent. The user's branch and working index were not reset, staged or switched.
Main was not merged. Private signing files exist only in the build checkout and
are excluded from the selected source, public source archive and release assets.

## Fresh verification

Flutter: 1737 tests PASS, analysis of lib/test/integration_test PASS. Backend:
313 suites / 4080 tests PASS after a clean install of the patched dependencies;
no skipped tests. The earlier run on old dependencies is retained as baseline
evidence and is not the final release proof. TypeScript, both expense/payment
OpenAPI checks and strict security gate 11/11 PASS.

Windows/HTTP/PostgreSQL journeys: 26 PASS, 43 requests, no 5xx. Includes employee
registration, network-loss draft recovery, payment replay, booking, completion,
cancellation, refund, concurrent editing, reopening persisted state, native
financial forms and synthetic isolated restore. Journey source fingerprint
`5590dfd3f4cfc25678ee21c41b2a8db858f649752af0fcc7a4e92bec2378521b` was recomputed
against the released working source; its Git HEAD field still names the user's
unchanged branch, not the release commit.

Deploy behavior/DB contracts, backup drill contract and exact-image startup,
healthy/degraded readiness and invalid-production-flags checks PASS. RepoWise
live-diff risk was elevated (81.5 percentile); no line-coverage map was available,
so complete client/server suites were run.

SAST: the final TS/Dart scan ran on 1339 files (~100% parsed), reporting 20 raw
findings; the general security-audit scan reported one overlapping CLI finding.
All were reviewed as non-exploitable/unchanged. The newly covered Ajv allErrors
finding is in the local contract-test helper excluded from the runtime build.
Gitleaks found five unchanged test/public-policy false positives in selected
source; confirmed secrets 0. Trivy image HIGH/CRITICAL 0, secrets 0. A general
scan partially parsed the CRLF Dockerfile; its unchanged pinned multi-stage,
non-root configuration was manually reviewed and the exact image passed runtime
gates. Initial scans that selected zero files are not treated as verification.

Windows ZIP and Inno Setup built with product version 1.5.33+213. APK/AAB package
magic.crm, version 1.5.33, code 213; existing signer SHA-256
`0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97` verified.
Release APK installed on API35 emulator; cold launch, empty-login field validation
and empty crash buffer PASS. Full employee journeys ran on Windows, not Android.
AAB signature verified with the existing self-signed certificate/timestamp/ZIP
ordering warnings. The emulator was stopped after verification.

## Production and published artifacts

Guarded cutover PASS. Public readiness reports database, migration and workers
healthy. Two commerce reconciliations returned `issues=[]`. Configuration SHA-256
is unchanged, preserving the owner's single-administrator OTP exception and all
other settings. Partial miss remains inactive; partial lesson remains active.
Expense rows missing their current revision: 0. No production test transactions
or manual financial-history changes were made.

| Artifact | SHA-256 |
| --- | --- |
| MagicMusicCRM-1.5.33-213-Setup.exe | ea7cb118e83eaa9fc44d237fbfa08a1a34b428036f8d01b4a50525bb4326553a |
| MagicMusicCRM-1.5.33-213-windows-x64.zip | 8903fc214ddd07d82e1f15ef8b725847b0b5d738104d2e4cdfb230b6152b0784 |
| MagicMusicCRM-1.5.33-213.apk | 7a8d2f6fd9e2c071e0e41b1f8de6d215cadd2b99d7436290d10f58321d600ecc |
| MagicMusicCRM-1.5.33-213.aab | 229fe27ca0a17df165e8c15e83f9744bccc41f367b19d8e89feea16a1d22cf10 |

Both public manifests select 213. Production file hashes and GitHub asset digests
match local files. GitHub release contains the four artifacts and SHA256SUMS:
https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.33

## Backup and rollback

Encrypted pre-cutover copy `magicmusiccrm-staging-20260909T183156Z.tgz.enc`, SHA-256
`88fd1a9d055a1b92298178cbe589f70ffc47764a0c77b5fd5b93c10ba02696f7`.
Post-release copy `magicmusiccrm-staging-20260909T183604Z.tgz.enc`, SHA-256
`113b155b950179238775dac8b69da59b87bbd4ded557d396d6b88a438a4bcfea`.
Both copied off-host, checksummed and restored in isolated Docker tooling with
candidate 213 and rollback 212. A separate preflight copy also passed. The drill
uses the corrected TCP PostgreSQL readiness check and reviewed legacy migration
baseline; it does not claim to prove historical SQL execution.

Compatible rollback image is `magicmusiccrm-server:1.5.32-212-final` at
`04aa69116bbf9d3c7e2df36e0825abc7b24a62a7`; schema stays at 0154. Never overwrite
new business activity with an old backup or roll back to a pre-0151 expense writer.
The known GNU signal/cleanup simulation limitation from release 212 remains
documented there; the full mocked failure harness is not labelled PASS here.

Remote operations: `/opt/magicmusiccrm/releases/1.5.33-213-0cf72120/`.
Local evidence: `dist/release213/`, journeys under
`dist/http-journeys/02bfe756f36e410a8e33b35e0a1a92d2/`. Private backups and secrets
are not release assets.
