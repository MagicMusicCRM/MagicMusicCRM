# Production release 1.5.37+217

Published with explicit owner authorization on 2026-09-10. Server/migration deployed before Windows and Android clients.

## Identity and behavior

- Tag v1.5.37; revision 694d6428a9b308425fa1a1df8805a9aa04ee87a0; selected source SHA-256 57a18e5ea45aec0168e13b4163c38235cc4d44083dde754931fb5656a0c5ac5d; 2194 selected files. Snapshot C:/Users/Alinka/mm217publish.
- Image magicmusiccrm-server:1.5.37-217-final; ID sha256:2891449c94586cad8690333e69df19e85a00b9dfa62ef66fbec7e0f3a6464de0; archive SHA-256 b7ba685db64a51d596157f7b360fc13c4ee828dcf09676ef9479cf02ed7b3846.
- Schema 0155_schedule_plan_archive. Operations /opt/magicmusiccrm/releases/1.5.37-217-694d6428/; evidence dist/release217/.

Subscription replacement follows the existing lifecycle chain. Coverage, future allocation and settlement resolve the active successor without rewriting snapshots, payments or completed facts. Increasing a package refills released reservations; decreasing it keeps the nearest eligible lessons within remaining units. Already consumed units remain consumed. The timeline displays reservations transferred to replacement contracts.

Ended individual plans expose an archive preview and confirmation with a mandatory reason. Active/group plans, non-cancelled lessons, linked payments, nonzero financial facts and reserved/consumed units block archiving. Archived cancellations disappear from the timeline; plan/reason/history remain in a collapsed archive. Server scope, version, fingerprint and idempotency are rechecked; database guards reject late financial operations. The audit event has an explicit Russian title.

## Verification

- Final full backend run: 313 suites / 4101 tests, all passed, zero pending. Fresh migrated isolated clone per suite; backend-tests-verified.log and backend-results-verified.json. Flutter: 1749 passed; lib/test/integration_test analyzer clean. Typecheck, build and both wire contracts passed.
- Windows/HTTP/PostgreSQL journeys: 26 passed, 43 requests, zero server errors. Real employee actions, retry, network failure, concurrent edits, booking, completion, cancellation/refund, and isolated restoration. C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM\dist\http-journeys\7212b0c637ac47548c9fb6da8ec8c2fe\result.json; source fingerprint 7ee35377ae4366e94b5caee059c69ad941ba4baf57bf4c24b025d81dd189a274.
- Final exact-image readiness/invalid-production-flags/degraded-503 gate passed. Strict security 11 passed. Native deployment/DB/behavior/backup contracts passed, including a separately pinned current image and rejection of an unexpected image/schema.
- Gitleaks: five unchanged reviewed synthetic/public findings, no confirmed secrets. Semgrep: 535 rules over 1872 files, 22 unchanged reviewed findings, no confirmed vulnerabilities. Final delta recheck covered deployment Bash, changed TypeScript tests and normalized Dockerfile; zero findings. Test harnesses use native checks. Bash heredoc partial parsing remains a documented scanner limitation. Trivy final image: zero HIGH/CRITICAL vulnerabilities or secrets.
- Windows Release, Setup and ZIP verified at 1.5.37+217. Signed APK/AAB verified; certificate unchanged. APK installed and cold-launched on API35, both login validation messages observed, crash buffer empty.

Initial failed runs are retained: a missing audit title was fixed; two SQL-specific test fixtures were updated for replacement lineage; the first overloaded test run also encountered a PGlite teardown/import error. The final full run passed. Build concurrency was reduced after memory pressure. Native build warnings remain in logs. The final reseal after runtime verification changed only tests and deployment tooling; runtime-evidence-continuity.json records this. The final server image was rebuilt and tested independently.

## Recovery and production data

Pre-cutover encrypted backup magicmusiccrm-staging-20260910T120911Z.tgz.enc, SHA-256 584078c49278e5202eac022c185f195539ae31ccc1dbf9686b085948f68e503e.
Post-release encrypted backup magicmusiccrm-staging-20260910T121627Z.tgz.enc, SHA-256 569a2ece92cacf356f6595c5bd804bcb335dcae0ab423d24e200f95a80566ee0.
Both were copied off-host, checksum verified and restored in isolation. Candidate migrations/reconciliation and recovery migration/reconciliation/schema probes passed.

The first restore drill correctly rejected stock server 216 because its strict migration runner lacks applied migration 0155. Recovery image magicmusiccrm-server:1.5.36-216-schema0155, revision 8ba14e67b43b589badf16d22aa56f117235a4a5f, version 1.5.36+216-schema0155, preserves every stock-216 runtime layer and adds only the two reviewed 0155 SQL files. Recovery identity is recorded in recovery-verification.json. The deploy script independently pins the running image and validates its revision and migration; recovery writes its own revision marker. Default deployments still require the running image to match the declared rollback image.

After client publication or any archive history, use a compatible forward fix retaining archive visibility and includeArchived. The schema-compatible stock-216 runtime is only a pre-client-publication fallback while no archived plans/lessons exist. Never rewind the database over new writes or run a down migration to erase archive history. Saved previous manifests can halt further upgrades but cannot downgrade installed clients.

Production reconciliation returned issues=[]. Common coverage preview examined 1 active subscription: changedLessons=0, reviewRequiredLessons=0. No repair/apply was necessary; transferred reserves already existed and are now displayed through lineage. Financial fact counts and SHA-256 fingerprints before/after this check match. Production environment checksum remains ed5e183be25cdec45aac1580a6dbd1b394ee7701819ff96c2355953b53a4205f, including the existing OTP exception. No production history was deleted or rewritten.

## Publication

https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.37

Both manifests select build 217. Public downloads were streamed and SHA-256 verified; GitHub asset digests match:

- MagicMusicCRM-1.5.37-217-Setup.exe: 61b4d58db402d359c2b5aa92d276724546ad00d0062314681063029a7ba17170
- MagicMusicCRM-1.5.37-217-windows-x64.zip: bcf6df5b8675603fa2e15874604a3a2c71ba1beff895aa26a4af6704518d4648
- MagicMusicCRM-1.5.37-217.aab: 1d196f94909d1e0fd0d533b02e006e7f3a50be42540cddf037be73edea34f99d
- MagicMusicCRM-1.5.37-217.apk: 6c560f2ffebb158714b2b330ca092104937ad77b02f801a2fab576d9a996a96f

The user's working branch and index were preserved with isolated release/evidence indexes. This release did not start a new user Windows session. The separate subscription-renewal work queue remains outside this release.
