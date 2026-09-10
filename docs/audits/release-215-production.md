# Production release 1.5.35+215

Published with explicit owner authorization on 2026-09-10 (Europe/Moscow). Client and server released together; release 214 fixes retained.

## Identity

- Tag v1.5.35; source commit 4c34f743e3884d1a9636c7214d8736d64a7effac.
- Selected source SHA-256 edf929ead75a2432586bf697f8399084ffab1a7705e77aee23997cd591bbdcc3; 2186 files checked against working source, isolated build snapshot and canonical Git blobs.
- Image magicmusiccrm-server:1.5.35-215-final; ID sha256:6e0bee44451f474c036007568b12281edafe1794e6a1351c3f22ec73a4d5919d.
- Image archive SHA-256 86e84411f87322d5d5d76c325326bb9827b6de9b92c81b1f8a6fdb85afec2b0b; transferred archive checksum and loaded remote image ID verified.
- Schema 0154_retire_partial_miss, no new migration.
- Snapshot C:/Users/Alinka/mm215publish; local evidence dist/release215/; remote operations /opt/magicmusiccrm/releases/1.5.35-215-4c34f743/.

## Released behavior

The lesson timeline hides days without lessons independently in each calendar row, keeping the three-past/twelve-including-today and following-fifteen-day windows. Compact cards have a minimum width of 39 logical pixels instead of 78, date and informational icons; time and details remain available in the tooltip and lesson window. Unpaid absence and free lesson decisions show a no-charge icon and explanation.

Automatic completion checks personal-account funds and paid subscription capacity, including installments, before recording student charges or teacher accruals. Funding shortages immediately leave the calculation for staff review; money and teacher accrual are not posted. Expected funding review is separate from technical retries and does not create false degraded readiness. The failure reason survives recovery after a crash. Account locks serialize concurrent spending, and both UI finance projections and completion use the shared subscription funding SQL. Manual resolution remains an explicit existing versioned staff command; topping up alone does not approve a pending review.

Archiving recurring series and a dedicated staff subscription-renewal queue remain proposals in docs/audits/lesson-timeline-funding-followup-2026-09-10.md; neither is claimed as implemented.

## Fresh verification

- Flutter 1743 PASS; analyzer lib/test/integration_test: no issues.
- Backend 313 suites / 4090 tests PASS, zero pending; clean migrated database clone per suite. Typecheck, build and both wire contracts PASS.
- Windows/HTTP/PostgreSQL: 26 PASS, 43 HTTP requests, zero server errors. Real employee flow covers student creation, payment, booking, completion, cancellation, refund, network interruption, retry/double-submit, concurrent editing and reloaded persisted state. Isolated journey backup restoration also passed. Evidence C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM\dist\http-journeys\ba469d3766ae4d68992284fc281b4948\result.json; source fingerprint df69f33ec1ca47590cfb131b889e5209b23693b4bdc85c8798ca41f23daca58c.
- Strict security 11 PASS, zero warning/failure. Deployment, DB, behavior and backup contracts PASS. Exact image checks: invalid flags fail closed, readiness/healthcheck pass, degraded readiness returns 503.
- Windows Release/Setup/ZIP built with production API and build 215; executable version 1.5.35+215 and setup version 1.5.35.215 verified. Signed Android APK/AAB built; release APK installed/cold-launched on API35, required login fields validated, crash buffer empty. APK versionName 1.5.35/versionCode 215. Signing certificate SHA-256 0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97 preserved.
- Gitleaks: five reviewed synthetic findings, zero confirmed secrets. Semgrep: 22 reviewed findings, zero confirmed vulnerabilities. The production Dockerfile parsed successfully after line-ending normalization. An existing Bash heredoc parser limitation remains at deploy-api-release.sh:678-915; this file is byte-identical to release 214, native bash syntax and fresh deployment contract/behavior checks passed. This is recorded as incomplete SAST coverage, not a zero-error scan. Trivy HIGH/CRITICAL vulnerabilities and secrets: zero.

Initial failed runs are retained: the first full Flutter run rejected a long dash in release notes; the final corrected complete run passed all 1743 tests. Initial strict security rejected a trailing blank line, corrected before the final gate. Remote image formatting initially failed after a successful checksum/load; the subsequent explicit image-ID check passed. Native linker/CMake and existing Android font/tree-shaking warnings are retained in build logs.

## Production and recovery

Fresh pre-cutover backup magicmusiccrm-staging-20260909T222020Z.tgz.enc, SHA-256 fb9ca79f99281ca973f71d2bb89e6b4ae6ea411e454a807a24dbc193708c9b8e.
Post-release backup magicmusiccrm-staging-20260909T222659Z.tgz.enc, SHA-256 5698d2c798d8e52d316ccf701cf3cdd7189dc5e2fc341dd4a9e9376ba9880307.
Both encrypted copies are off-host, checksummed, and restored into isolated Docker databases. Candidate migrations/reconciliation, rollback image migration compatibility/reconciliation and final schema probes passed. No production financial or lesson history was rewritten; no coverage repair apply was run for this release.

Guarded production cutover and final V7 reconciliation passed (issues=[]); public readiness ok. Production .env checksum ed5e183be25cdec45aac1580a6dbd1b394ee7701819ff96c2355953b53a4205f unchanged, retaining the owner-authorized single-admin OTP exception.

Rollback target: magicmusiccrm-server:1.5.34-214-final, revision 48647ccd1bf09ff760ecb7f318ed33b8dd51af85. Use rollback.override.yml through the guarded deployment process; retain schema 0154 and new financial/audit facts. Do not rewind the database over new operations. Prior manifests can halt further client upgrades; already upgraded clients need a forward fix. Existing GNU signal-harness limitation from release 212 remains, not claimed as newly passing.

## Publication

https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.35

Both public manifests select build 215. Four public downloads were streamed and SHA-256 verified; GitHub asset digests match:

- MagicMusicCRM-1.5.35-215-Setup.exe: bae2addb1588ff8dd12f18a593e8b2beea700488609628a93ca87e890b38c9b6
- MagicMusicCRM-1.5.35-215-windows-x64.zip: 5cbaa38a3a23844c284816e2dddecfead8339857d40b7dd6dd43ddc3e7ca7dc1
- MagicMusicCRM-1.5.35-215.apk: 5d3fda4598539acc35ffef61e279ae771841cd8b22a1d21aac3643ca388effac
- MagicMusicCRM-1.5.35-215.aab: da3a6437d0faac74f4b1e7e3d4eb4a4be4461af24158931bfbbd9a8a12b7e1fc

Source release and operational evidence use isolated Git indexes/commit-tree. The user's working branch and index were preserved.
