# Production release 1.5.38+218

Published with explicit owner authorization on 2026-09-10. Server deployed before Windows and Android clients.

## Identity and behavior

- Tag v1.5.38; revision 078b32e6f48b0396633188df355716a5427c3f5e; selected source SHA-256 4612385ce35b506f113022757d37127286358b5d907de3fe0e875f624b1f1720; 2198 selected files. Snapshot C:/Users/Alinka/mm218publish.
- Image magicmusiccrm-server:1.5.38-218-final; ID sha256:b7147997a79354aeec526a6ab8d11a4de2a4659c2ae01204864dba081ff79be8; archive SHA-256 5749e344cd4e156d93164479d1262ef3dc332501bc6d150874d66c0a7e77602b.
- Schema remains 0155_schedule_plan_archive. Operations /opt/magicmusiccrm/releases/1.5.38-218-078b32e6/; evidence dist/release218/.

Subscription replacement issues the full new package. Unused old value is credited at the old issued price; consumed value remains spent. Debt/overpayment includes actual confirmed payments and prior obligations across the chain. Financing and cancellation subtract historical consumed value, including personal-account purchases. No automatic cash refund or free refill occurs. Unfunded completed lessons retain administrative review without actual student charges or teacher accruals. Old payments, snapshots and completed facts are preserved.

Future planned lesson reads resolve the active subscription for list and schedule matrix after role/scope masking. Nearest eligible lessons receive reservations through the existing allocator. Historical/effective decisions retain their original IDs. The replacement preview displays full volume, unused-value credit and financial result. Release217 timeline and individual-plan archive fixes remain included. Product formulas and examples: ../architecture/subscription-full-volume-replacement.md.

## Verification

- Full backend: 315 suites / 4115 tests passed, zero pending/failed; fresh migrated isolated clone per suite. Flutter: 1749 passed, lib/test/integration_test analyzer clean.
- Windows/HTTP/PostgreSQL employee journeys: 26 passed, 43 HTTP requests, zero server errors. Persistence, network interruption/retry, repeated commands, concurrent edits, booking, settlement, cancellation/refund and isolated restore covered.
- Strict security: 11 PASS / 0 WARN / 0 FAIL. Wire contracts, deploy/schema/behavior and backup contracts, Bash syntax, exact-image health/config/degraded-readiness checks passed.
- Gitleaks: five reviewed synthetic/public findings, no confirmed secrets. Semgrep: 532 rules / 1876 files; 22 reviewed findings, no confirmed vulnerabilities. Recheck resolved large-test timeout and Dockerfile parsing; existing Bash heredoc partial parsing remains, covered by native syntax and behavior checks. Trivy final image: zero HIGH/CRITICAL findings or secrets.
- Windows Release/Setup/ZIP report 1.5.38+218. Signed APK/AAB verified with unchanged signing certificate. Release APK installed and cold-launched on API35; login validation observed and crash buffer empty.

The initial Android --no-pub build failed because a generated registrant retained the integration-test plugin. Rebuilding with Flutter dependency/plugin regeneration removed it without changing selected source; signed release builds and source identity were rechecked. Native SDK/font/CMake/linker warnings remain in build logs. Source identity was checked across the working tree, snapshot and canonical Git blobs before cutover. Documentation-only operational status updates below belong to a separate evidence commit.

## Backups, recovery and production data

Pre-cutover encrypted backup magicmusiccrm-staging-20260910T130931Z.tgz.enc, SHA-256 7a9ead86e64adddf47126a3873d78e22330928fa9646b3dcb7658931f70ee333.
Post-release encrypted backup magicmusiccrm-staging-20260910T132434Z.tgz.enc, SHA-256 f568cf771886b213d8f56ca14ea078f60b23878530d16fadc55b301c9cf60346.
Both copied off-host, checksum verified and restored in isolation with candidate and compatible recovery; migration, reconciliation and schema probes passed.

Recovery image magicmusiccrm-server:1.5.37-217-recovery218, revision e018f8321d17f98a7a9107a83ce6c608086c68cd, version 1.5.37+217-recovery218, retains release217 plus identical current funding/cancellation/context modules and a fail-closed replacement guard. Compiled module SHA-256 identity and the guard were tested. Replacement is temporarily unavailable in recovery; current financial semantics and archive visibility remain supported. Stock217 must not run after full_volume operations. Prefer forward fix. Never rewind the database, erase facts or run down migrations over new history. Previous manifests can stop further upgrades but cannot downgrade installed clients.

Production reconciliation returned issues=[]. Coverage preview: 1 active subscriptions, 0 changes, 0 review-required lessons. No repair/apply was needed. Financial fact row counts/SHA-256 match before/after at the same cutoff. Production environment checksum remained ed5e183be25cdec45aac1580a6dbd1b394ee7701819ff96c2355953b53a4205f; existing OTP exception preserved. No manual deletion or history rewrite.

## Publication

https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.38

Both manifests select build218. Public downloads were streamed and SHA-256 checked; GitHub asset digests match:

- MagicMusicCRM-1.5.38-218-Setup.exe: 6ea6b076d0ca35e7d4e52b30b4ef2ceddc1f775520286a09bba8fdf4c8e3dac4
- MagicMusicCRM-1.5.38-218-windows-x64.zip: 94d6122bb907614da89785f66d9ce99881c047a53acd921ac789e52ff9ca8510
- MagicMusicCRM-1.5.38-218.apk: db336c5fa59fc6a4b2a6f57589dbfb59d1de2030465ec8124e613766f7f8bb97
- MagicMusicCRM-1.5.38-218.aab: f07462ace48c74dd841da8331bac15ce5220a55bc53a7d95626330590ef632be

The working branch and normal index were preserved using isolated release/evidence indexes. No new user Windows app session was started. Separate subscription-renewal notifications remain outside this change.
