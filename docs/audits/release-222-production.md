# Release 1.5.42+222 — 2026-09-16

Status: **DEPLOYED AND PUBLICATION VERIFIED** — server and clients 1.5.42+222.
The owner explicitly authorized deployment and waived Windows Sandbox
clean-install/upgrade UAT. The earlier SSH/TLS outage was resolved by the owner
(server billing); fresh SSH and public readiness checks passed before deployment.

## Exact release identity

- Source commit/tag: `e8cbb20fd609716ff6b585c765adb19db397cd1c` / `v1.5.42`.
- Server: `magicmusiccrm-server:1.5.42-222-final`, image
  `sha256:750a0114d7f446b8f94bfeb84218d88574dfbcab6573a5af2ce4be65330e08fe`.
- Schema: `0156_trial_lesson_catalog`; prior production was 221/schema0155.
- Frozen source: 2137 files, SHA256
  `7d917924a5c8c286c9ce4f40b6c1c67161aa7738ca59e052e05be5ae9ab0f03c`.
- Evidence directory: `dist/release222-final/` (ignored; no backups/secrets committed).

The fresh server build has release revision/version labels. Its compiled `dist`,
`db`, `node_modules`, package and lockfile hashes are identical to the previously
verified customer-revision image; see `runtime-equivalence.json`. Full backend
317 suites/4136 tests and Flutter 1797 PASS/0 FAIL/4 intentional updater skips
remain applicable to unchanged source. Updater tests passed separately. No new
full-suite run is claimed. Exact final server image health/degraded checks passed.

Windows ZIP matches all 31 Release files. Fresh Android APK v2 signing and AAB
jarsigner verification pass; certificates match production:
`0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
Windows Setup remains unsigned, as in the previous release. Embedded client
release history retains its original September 13 preparation date; actual
deployment occurred September 16.

## Backup and compatible rollback

Both encrypted backups were copied off-host to `dist/backups`, checksum-verified,
and restored in isolated Docker networks against the exact candidate and recovery
images. Candidate migration/reconciliation and recovery migration/reconciliation
passed. Production databases and history were not replaced.

| Backup | SHA256 |
| --- | --- |
| `magicmusiccrm-staging-20260916T095740Z.tgz.enc` (pre) | `c291dd767d77fabf9f6f4e88875dc2a2ccc6d59b5463012c4e76be9a765dc7ca` |
| `magicmusiccrm-staging-20260916T100523Z.tgz.enc` (post) | `eba471863023ce80ef5167ca9a824d66c7210a9f8556f48b804e92c6a66470ae` |

Recovery: `magicmusiccrm-server:221-recovery-0156-c59fd72bb33e`, image
`sha256:bd341e0bb67564d3cb4c466addb496ca517570628c0972a2e51cc6a8396e919d`.
It supports schema0156 and teacher-pay filtering. The prior image-switch test
passed 27 checks/58 HTTP requests, including nonzero pay, XLSX equality, preserved
manual pay and unchanged history. Shared financial code is not an independent
fallback for a defect in that code. Never use stock221 after0156 or down-migrate.

Remote release directory: `/opt/magicmusiccrm/releases/1.5.42-222-e8cbb20f`.
The reviewed deploy script preserves migrate-before-main, all production workers,
health/readiness checks and fail-closed automatic compatible rollback. Previous
client manifests/history are retained in its `rollback-manifests/` directory.
Restoring channels stops further updates but cannot downgrade installed clients.

## Production checks

`cutover.log`: `DEPLOY_API_RELEASE|PASS`. Exact deployed revision/image/schema
confirmed in `production-postflight.log`; public readiness returns `status=ok`
with schema0156. Reconciliation reports `issues=[]`.

Existing lesson client charge and teacher compensation facts (7 rows each) are
unchanged at cutoff `2026-09-16T10:02:03.036Z`; counts and SHA256 match before/after.
This is an explicit check of those two append-only fact tables, not a hash of
the entire live database. Evidence: `financial-history-comparison.json`.

Read-only production catalog check confirms an active free-client `trial_lesson`
type, default teacher rule `trial_lesson` and active zero-pay teacher rule.
No synthetic lessons, payments or clients were created in production.

## Publication

All four public artifacts were streamed and SHA256/byte counts matched local
files. Both `latest.json` and `latest-v2.json` return build222/version1.5.42+222,
the expected Windows ZIP URL/hash; public release history starts with build222.
Evidence: `public-verification.json`, `artifact-manifest.json`.

[GitHub Release v1.5.42](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.42)
is published (not draft/prerelease); all four GitHub asset digests match.
The release source commit and tag were pushed. Unrelated `.claude/CLAUDE.md`,
outputs and generated build info were not included. RepoWise update reported
already up to date. Git auto-GC reported an existing bad tree object while
committing; the release commit succeeded, its full source archive was readable,
and both branch/tag pushes succeeded. No destructive repository repair was attempted.

| Artifact | SHA256 |
| --- | --- |
| Windows Setup | `7825981d4337b97bada22379cc543a893a5bfcdce27bb1581759d2bad1ea2ad8` |
| Windows ZIP | `b391324efc93733f32d1e61f140e1ac5051bf5c9e8050b15e001a4417b3517a0` |
| Android APK | `7a8dda7cc8725157afd622faf1d2d1caf87d7920fc9884ad674c3a8198a7421e` |
| Android AAB | `76ba3d28ff371dd31ec356b9e23a779497673732f4fd7e8713a3481721e9798e` |

## Acceptance limits

Windows Sandbox install/upgrade was owner-waived, not PASS. Android acceptance
uses a local Debug build with real UI/API: login, navigation, move-save and reopen
were checked. One aggregate verifier failure was corrected and recorded response
revalidated; it was not silently converted into a new full live PASS. Details:
[preproduction evidence](customer-revisions-preproduction-2026-09-13.md).
No physical-device, signed-release authenticated or push-delivery claim is made.
Weekly drag-and-drop remains out of scope.
