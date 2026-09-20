# Production release 1.5.41+221

Published with explicit owner authorization on 2026-09-12. Server was deployed
before the client channels.

## Identity and scope

- Tag `v1.5.41`; revision `0a7b6e1742f9456099e3023298ad84883e51a8e2`;
  source SHA-256 `b519afd143b6c36360ef34d94c5c944a4b2ca13ef612fc7196f7d9c858410e4c`.
- Server image `magicmusiccrm-server:1.5.41-221-final`, image ID
  `sha256:08042ab5de8fd328ac91d4276b13760a738f9882cac060a6045d0273fd886408`;
  archive SHA-256 `9c965e3e48ef8464440ddba5dcaf35fc07855e8a9b66263b57b9f9ceae98cd84`.
- Operations: `/opt/magicmusiccrm/releases/1.5.41-221-0a7b6e17/`.
  Evidence: `dist/release221/`. Schema remains `0155_schedule_plan_archive`;
  the normal migrator ran and found no new migration.

The release fixes complete form persistence, deep links from indicators and
notifications, branch context in schedules, unified comments with author/role/time,
group messenger actions, pagination, attachments and RBAC behavior found by the
full CRM audit. Teacher comments remain comments and are visible to teachers and
administrative roles.

## Verification

- Full Flutter: 1777 passed with four intentional skips. Full backend: 316 suites,
  4124 tests passed. Scoped Flutter analyzer, backend typecheck/build, security,
  API and deployment/backup contract gates passed.
- Access inventory has 356 scenarios; all 344 private scenarios are explained and
  there are zero unexplained allows. The production image passed exact metadata,
  healthy readiness, degraded 503 and fail-closed checks.
- Windows Setup/ZIP and signed Android APK/AAB were built and signature checked.
  Both public update manifests select build 221. Every public artifact was streamed
  after publication and matched the local SHA-256. GitHub Release and source tag
  were also published.
- Production postflight identifies exact revision, image ID and version. Public
  readiness is HTTP 200 with database, migrations, workers, outbox and V4 rollout
  healthy. Reconciliation returned `issues: []`.

## Recovery and data

Pre-cutover backup `magicmusiccrm-staging-20260912T192047Z.tgz.enc`, SHA-256
`1d9fb839b95b864adaa9706ba45fca632bc6afaa1e3efa5951c4a28dd54d8bf2`.
Post-release backup `magicmusiccrm-staging-20260912T192858Z.tgz.enc`, SHA-256
`fecaaf9c4695cbd51c79bd290748ddf8c60f7ea69c787378fb74d5bda1a459d9`.
Both encrypted backups were copied off-host, checksum checked and restored in
isolated databases with candidate 221 and rollback 219. Migration, readiness and
reconciliation probes passed in both drills.

Financial charge and teacher compensation facts were hashed at the same cutoff
before and after cutover: both tables retained six rows and identical SHA-256.
No manual repair, deletion or history rewrite was performed.

Rollback uses `magicmusiccrm-server:1.5.39-219-final`, revision
`2f37c7aee4633a463ba8fad3e322e0d945e50a23`, image
`sha256:f9d80b7831895395376777d83a0b7b1d609140bb0dff0d9614d7673b3bba6bf0`.
Keep schema 0155 and all financial, teaching and audit history. Preserved version
220 manifests can stop further client upgrades but cannot downgrade installed
clients; prefer a forward fix after publication.

## Publication

https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.41

- `MagicMusicCRM-1.5.41-221-Setup.exe`: `2f396614c92dfee269ebeacf5fc743affef7244d7b70c82d655b3b1d928d4f87`
- `MagicMusicCRM-1.5.41-221-windows-x64.zip`: `0df14da9a76bec830559f2008df8cc154b5ce94e0f953a9691bb8dde57711b42`
- `MagicMusicCRM-1.5.41-221.apk`: `38d088a012af5edcb80d19d9baccc3d6dc9a6ebbeeba4f8d279d15a6c8707f19`
- `MagicMusicCRM-1.5.41-221.aab`: `e5db07a445e5cb3b3b0a302930fc6268ec75a533689d90ca239ee4cf7c62e9f7`
