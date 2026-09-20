# Production release 1.5.34+214

Published with explicit owner authorization on 2026-09-10 (Europe/Moscow). Client and server released together. All release-213 fixes remain included.

## Identity

- Tag: v1.5.34; release commit: 48647ccd1bf09ff760ecb7f318ed33b8dd51af85.
- Selected source SHA-256: f38cb82ee0333fbb530c558a630704ce2f1ea0d85c8059bbae82d513971abc2e; 2182 files verified against working source, build snapshot and canonical Git blobs before deployment.
- Image: magicmusiccrm-server:1.5.34-214-final; ID: sha256:494923258ba0e9857c304b8f09515be7523626db0cf412ee551b655ec9cf0fed.
- Image archive SHA-256: 930eeb295dc81edf24c5a89ffea800040594bd6952d6307d3781a6ed36489100; remote copy verified.
- Schema remains 0154_retire_partial_miss; no new migration.
- Build snapshot: C:/Users/Alinka/mm214publish.
- Operations: /opt/magicmusiccrm/releases/1.5.34-214-48647ccd/; local evidence: dist/release214/.

## Behavior

The calendar feed reads left to right: row 1 has three past days plus twelve days including today; row 2 has the next fifteen days. Cursor pages within each calendar window load atomically. A failed window load keeps the preceding window available.

Shared subscription allocation reserves eligible uncompleted lessons chronologically, independent of creation order. Existing consumed facts, explicit funding decisions, historical exceptions and replacement mappings are preserved. The planned-settlement edit alias no longer sends the forbidden reasonCode; reasonText is retained.

The repair entry point is compiled into the production image at dist/migration/commerce/v8/reconcile-subscription-coverage.js; the development scripts entry point delegates to the same source. Preview is the default and rolls back reservations, audit and outbox. Apply requires --apply and uses the existing coordination gate and subscription locks.

## Fresh validation

- Flutter: 1740 PASS; source analyzer lib/test/integration_test: no issues.
- Backend: 313 suites / 4082 PASS, clean migrated clone per suite; typecheck and both wire contracts PASS.
- Windows/HTTP/PostgreSQL journeys: 26 PASS, 43 requests, zero server errors. Evidence: C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM\dist\http-journeys\74ecfd38fbaa4d468fe448e076c64ead\result.json; source fingerprint 1fbf65eb761709e2a9819e034d66c7b5e98ea63addf4ea2db6c92b6a246f8a57.
- Strict security gate: 11 PASS, zero warnings/failures. Deploy contracts, DB contract, deployment behavior and backup contract PASS.
- Exact image: invalid flags fail closed; healthy readiness and Docker healthcheck PASS; degraded readiness returns HTTP 503.
- Release Android APK installed and cold-launched on API35; empty login shows both field errors; crash buffer empty. APK/AAB signatures verified; APK versionCode 214/versionName 1.5.34. Production signing certificate SHA-256 remains 0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97.
- Gitleaks: five reviewed synthetic fixtures, zero confirmed secrets. Private signing material excluded from selected source and Git. Semgrep: twenty reviewed findings, zero confirmed vulnerabilities; timed-out scans of seven files rerun successfully with zero findings/errors. Trivy HIGH/CRITICAL vulnerabilities and secrets: zero.

Initial runs are retained, not presented as successful: stale timeline/calendar fixtures and MSIX metadata were corrected; two transient shader-asset test failures disappeared in the complete sealed 1740-test run. Initial local API startup and image-invalid-flags checks timed out under build load; the same unchanged runtime passed the complete retries. An unavailable Semgrep p/dart configuration was replaced with p/default and p/security-audit. A broad analyzer scan found one existing lint only in outputs/application-audit-2026-09-05; release source analyzer passed. Native Windows linker/CMake and Android SDK/tree-shaking warnings remain recorded in build logs.

## Recovery and production

Pre-cutover encrypted backup: magicmusiccrm-staging-20260909T205845Z.tgz.enc; SHA-256 7b4bc7be08bedd087d4b8ea306b681ba8621804123b3bb4d3962cc61e2603ee3.
Post-release encrypted backup: magicmusiccrm-staging-20260909T210432Z.tgz.enc; SHA-256 288cbe8b3bf44949c9296036d71d83576ffdcedb99e0b60ae16456e8c09093fa.
Both copied off-host, checked and restored into isolated Docker databases with candidate and rollback images. The actual pre-release data rehearsal changed coverage for two lessons; every financial and lesson table remained identical. Only reservations, audit and outbox changed; reservation history was preserved. Preview rolled back all changes; repeated apply wrote nothing. Post-release restore had zero changes/review-required lessons.

Guarded production cutover PASS. Production preview and apply: one subscription, two changed lessons, zero review-required lessons. Repeated apply: zero changes. Before/after/final V7 reconciliation: issues=[]. Public readiness: ok. Production environment checksum remained ed5e183be25cdec45aac1580a6dbd1b394ee7701819ff96c2355953b53a4205f; authorized single-admin OTP exception preserved.

Rollback: magicmusiccrm-server:1.5.33-213-final, revision 0cf7212052f5caea9fbad7c010fc096dc6f5bb86. Use reviewed rollback.override.yml through the guarded deployment process; retain schema 0154 and new financial/audit history. Both restore drills verified rollback migration/reconciliation after coverage application. A client already upgraded needs a forward fix; prior manifests can halt further upgrades. GNU signal-harness limitation documented in release 212 remains unchanged; it is not claimed as a newly passing full harness.

## Publication and local launch

https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.34

Both public manifests select build 214. All four public downloads were streamed and verified by SHA-256; GitHub asset digests match:

- MagicMusicCRM-1.5.34-214-Setup.exe: 32f02b9b602745d2f065ee791fb1e47106aecfaf9d3422c9e2d9d878fdc45692
- MagicMusicCRM-1.5.34-214-windows-x64.zip: e439f99ab269c55fffa80f4a40aa743dba6eb196f5d159b6bed7e7eb230a0d79
- MagicMusicCRM-1.5.34-214.apk: 790ae0157d81042277c796f58b7ee04dc3a152155fed0f7911718481d78d3b24
- MagicMusicCRM-1.5.34-214.aab: 7edfdc5daf59cef7ff633917cc4acba2c4b548928fdfcf3afd5a9d725e862ecd

Launched Windows 1.5.34+214, PID 15176, from C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM\dist\release214\windows-package\magic_music_crm.exe. Process responsive with a visible application window. Existing older preview processes were not terminated.

The release tag and operational evidence use an isolated Git index/commit-tree; the user's working branch/index were preserved.
