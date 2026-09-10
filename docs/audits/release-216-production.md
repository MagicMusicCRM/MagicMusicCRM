# Production release 1.5.36+216

Published with explicit owner authorization on 2026-09-10 (Europe/Moscow). Server and all four client artifacts published together.

## Identity

- Tag v1.5.36; revision bd5eb5e437bef632a8a690dd3b78940a5c8cd601.
- Selected source SHA-256 be3ee6732ee8eaed7fd0ed0c96f9ba1b7778b6dc5f0e51b68c075256675815cf; 2186 files verified against working source, build snapshot and canonical Git blobs.
- Image magicmusiccrm-server:1.5.36-216-final; ID sha256:02331cdcd3c4f4e41d39c02c89f818277e765c06d56049089844b5422cc14109; transferred archive SHA-256 6a25e787060f4d15e8825df0eaf4e6a9956fb587bb3d6b1d8d6b1ce21c0dcc6e.
- Snapshot C:/Users/Alinka/mm216publish; operations /opt/magicmusiccrm/releases/1.5.36-216-bd5eb5e4/; evidence dist/release216/.
- Schema remains 0154_retire_partial_miss; no new migration or manual data repair.

## Correction

The prior layout calculated narrow widths for about thirty columns while rendering two rows, leaving half the container empty. Its thirty-calendar-day request then hid empty days, leaving fewer occupied dates (22 in the owner's screenshot).

The new page collects thirty occupied local dates from the initial midnight three calendar days before today. The first fifteen dates occupy row one, the next fifteen row two, in chronological order. Fifteen columns share desktop width, including the actual container borders; narrow screens and larger text keep horizontal scrolling and a minimum width of 39 logical pixels. Date, icons, tooltips and lesson opening are preserved. When fewer dates exist, only real lessons are shown.

The existing timeline API accepts an optional validated anchor for the first request, then opaque keyset cursors. RBAC, resource scope and the same repository are preserved. The client reads through the thirtieth date, including a date split across API pages, then stops on the next date or end of data. Backward loading chooses the nearest thirty dates and renders them ascending. Empty adjacent pages preserve current content and disable exhausted navigation; failed requests preserve the last complete page and can retry. Financial rules from release 215 are unchanged.

## Fresh verification

- Flutter 1746 PASS; analyzer lib/test/integration_test: no issues.
- Backend 313 suites / 4095 PASS, no pending tests; clean migrated clone per suite. Typecheck, build and both wire contracts passed.
- Windows/HTTP/PostgreSQL employee journeys 26 PASS, 43 requests, zero server errors; payment retry, network loss, concurrent edits, booking/completion/cancellation/refund and restored persisted facts. Evidence C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM\dist\http-journeys\22ff00e2306c4d84ada41d37f1738be7\result.json; source fingerprint e4adddd8e2407bd1595b7a6d0e9f0bb39637ba34b2ee897f236675ec55541cc8.
- Focused before-fix widget test reproduced the missing dates/unused width. Targeted tests then passed for thirty sparse dates across months, complete final-day pagination, backward ordering, empty-page preservation, cell bounds, tooltip details and narrow-screen scrolling. Visual render inspected from the same widget.
- Strict security: 11 PASS, no warning/failure. Deployment, database, behavior and backup contracts passed. Exact image rejects invalid flags, passes live/readiness/healthcheck, and returns 503 when degraded.
- Gitleaks: five reviewed synthetic findings, no confirmed secrets. Semgrep findings reviewed against unchanged source where applicable; no confirmed vulnerabilities. Existing Bash heredoc partial parsing in deploy-api-release.sh remains documented; native syntax and deployment contract/behavior checks passed. Trivy image HIGH/CRITICAL vulnerabilities and secrets: zero.
- Windows production Release/Setup/ZIP built. Signed APK/AAB built; release APK versionName 1.5.36/versionCode 216 installed and cold-launched on API35, required login errors verified, crash buffer empty. Signing certificate SHA-256 remains 0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97.

Expected initial regression failures and subsequent passes are retained, rather than counting the failing runs as release passes. The stale calendar-window test fixture was updated for anchor pagination, including a fixture-only Dart list typing correction; the complete final Flutter run passed. The first Android --no-pub build retained integration_test in generated plugin registration; rebuilding with normal Flutter preparation regenerated that excluded build file and both release outputs passed. Existing native build warnings and scanner parser limitations are retained in logs.

## Recovery and production

Pre-cutover backup magicmusiccrm-staging-20260910T000002Z.tgz.enc, SHA-256 c9f9bfdd083c0cd15fbbc5c8f5e39a9117282207615c3d3ed9954789e9320326.
Post-release backup magicmusiccrm-staging-20260910T001214Z.tgz.enc, SHA-256 cd0ecf6acd95a5908e65ce31e07834f22bff6bf80dbfa496f80d488bbfa68b90.
Both encrypted archives copied off-host, checksum verified, and restored to isolated databases. Candidate migration/reconciliation, rollback migration compatibility/reconciliation and final schema probes passed. Production reconciliation issues=[]; public readiness ok. Production environment checksum unchanged, including the authorized OTP exception. No financial or lesson history rewritten.

Rollback image: magicmusiccrm-server:1.5.35-215-final, revision 4c34f743e3884d1a9636c7214d8736d64a7effac. Retain schema 0154 and new facts; never rewind the database over new writes. Rollback to 215 is safe before client publication. After clients upgrade, preserve the new optional anchor API in a forward correction; old 215 does not accept that query parameter. Prior manifests can stop additional client upgrades but do not downgrade installed clients.

## Publication

https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.36

Both manifests select 216. Public downloads were streamed and SHA-256 checked; GitHub asset digests match:

- MagicMusicCRM-1.5.36-216-Setup.exe: 52bb1cdfb26de26e14aa59a6a0d787cf52b694cd2bc63edd3971390ed1c18537
- MagicMusicCRM-1.5.36-216-windows-x64.zip: e51f75bb6c16899007d4188b063ea401f542334b83f89f599d417f76f9612ce0
- MagicMusicCRM-1.5.36-216.apk: 0e07d48dc02584565e6b59c1a00de6341a0749a168a7972bd199fe0f012a457b
- MagicMusicCRM-1.5.36-216.aab: bfd50afe6ee57896e8511043ce9bf19c23b8f2d39b74c3bdbb2ecd1121f3a5f6

An isolated Git index and commit-tree preserved the user's branch and index. No new user Windows session was launched by this release.
