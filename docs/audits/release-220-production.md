# Production client release 1.5.40+220

Published with explicit owner authorization on 2026-09-10.

## Scope and identity

Client tag v1.5.40, revision 7ddb5b2b8fb5fe8e8d823cf4d6fa95c9cdd0c563, source SHA-256 9786a630a2e261537b990e3f9b043e1fd6af6e2c4891ad7094d785d880879428.
Snapshot C:/Users/Alinka/mm220publish contains all 3310 tracked baseline files and
exactly six overrides: the pager, its regression tests, version metadata and release history.
Unrelated working-tree modifications are excluded. Evidence: dist/release220/.
Flutter regenerated seven tracked plugin-registration files with LF instead of
the snapshot's CRLF. Their bytes match the canonical Git blobs; verification
records both hashes and rejects any change beyond those line endings.

Server stays on 1.5.39+219, revision 2f37c7aee4633a463ba8fad3e322e0d945e50a23, image
sha256:f9d80b7831895395376777d83a0b7b1d609140bb0dff0d9614d7673b3bba6bf0.
No server cutover, migration or production data mutation was performed.

## Correction

Version219 introduced a ScrollController which read and wrote the same PageStorage
entry as its enclosing ExpansionTile. A saved expansion boolean could be cast to
a scroll-offset double; the release renderer displayed a grey ErrorWidget.
The shared pager now uses keepScrollOffset:false. Offsets belong to the pager and
reset with pagination; expansion persistence, stable viewport height and archive
restoration remain available. Reproduction failed before the fix with the bool/double
type error (dist/pager-archive-repro.log).

Windows/Android widget variants now repeatedly open the archive and reopen a client
card after actual internal scrolling with a preserved PageStorageBucket. Tests use
the production theme and scroll behavior; they verify visible records, no ErrorWidget,
the short last page and stable outer geometry.

## Fresh verification

- Full Flutter: 1756 passed, analyzer clean. Full backend: 315 suites / 4115 passed.
- Native Windows/HTTP/PostgreSQL employee release scenarios: 26 passed, zero server errors; restore verification included. Journey runtime and integration-test source match the release snapshot after explicit CRLF normalization. Local package test-runner commands differ; dependency definitions and lockfile match, and the runner launches the server directly.
- Strict security: 11 PASS. Expense/payment wire contracts match. New-commit Gitleaks scan: zero secrets. Unchanged production image healthy/degraded/fail-closed checks passed.
- Windows Release and Setup/ZIP built. APK/AAB signatures verified against the existing certificate. Android API35 cold launch, version220, required login field feedback and empty crash buffer verified.
- Public Setup/ZIP/APK/AAB streamed and SHA-256 verified. Both update manifests select220; GitHub asset digests and source tag match.

Pre-publication backup magicmusiccrm-staging-20260910T183653Z.tgz.enc, SHA-256 fefcccf680f734668dfdb7d4d2f53b0f07105d07e83018dae7b1e2ff5ffc088e.
Post-publication backup magicmusiccrm-staging-20260910T184624Z.tgz.enc, SHA-256 7d52a0d0792580a90e2149d75ec683f13545b13da0c26075c49d2726ce30174c.
Both encrypted backups copied off-host and restored in isolated databases using
server219 and the compatible stock218 rollback image. Production reconciliation
issues=[]; coverage preview unchanged; financial fact hashes at the same cutoff,
server identity and environment hash remain identical.

## Recovery

Preserved version219 manifests can halt further upgrades via atomic replacement;
they cannot downgrade already installed clients. Prefer a forward client correction:
219 has the known grey-block defect. Server and database remain in place. Do not
rewind financial, teaching or audit facts. See dist/release220/rollback-plan.md.

## Publication

https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.40

- MagicMusicCRM-1.5.40-220-Setup.exe: 4fda59714d7e6d7c1a7fbfaaf1314d1ceaf8b8007b9bdbf34305a61fab72206a
- MagicMusicCRM-1.5.40-220-windows-x64.zip: ff3c7d4fa72f0f60f4cd442cc97d094c1fcf6c4349763f65554135cb8a366d92
- MagicMusicCRM-1.5.40-220.apk: 68efcefcb119d9b1de52702b09b92a463e0cbe2e7b641e96afd4c885d8e9a5ef
- MagicMusicCRM-1.5.40-220.aab: ec45bfee94ce353aef3c774d0c435fadc04d15d5dab07f57222fe80286be7be5

Candidate and operations evidence use isolated Git indexes; the normal index is preserved.
