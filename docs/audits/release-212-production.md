# Production release 1.5.32+212 — 2026-09-05

Owner authorization: publish all fixes if fresh checks pass. Production deployed
by guarded cutover, then client artifacts/manifests and GitHub release published.

## Immutable release identity

- Source commit/tag: `04aa69116bbf9d3c7e2df36e0825abc7b24a62a7` / `v1.5.32`.
- Source manifest SHA-256: `955f626683233c8cc8ffaa6b8e1d1a592a79e63c8e75935d58ad56bed1c184ed` (2175 files).
- Image: `magicmusiccrm-server:1.5.32-212-final`; ID `sha256:942e0a99d837de688af6626d3c2157685195ae60ddfee232d0ac6bf7a31bc7ed`.
- Image archive SHA-256: `eb10a72fe9522b5a44112a79d63d4feee4418294bffb2714b69d08ab64a3b497`.
- Schema: `0154_retire_partial_miss`. Reviewed legacy baseline records 150 checksums; it does not prove historic SQL execution.

The source commit was created using a temporary index from the verified working
snapshot. The user's working index, branch and other uncommitted files were not
reset or staged. The release tag is pushed. Main was not merged automatically.

## Fresh verification

Flutter: 1726 tests PASS; analysis of lib/test/integration_test PASS. Backend:
313 suites / 4080 tests PASS on isolated databases. TypeScript, expense/payment
OpenAPI contract checks, strict security 11/11, deploy behavior/DB contracts and
exact-image healthy/degraded/invalid-production-flags gates PASS.
Semgrep 19 findings and Gitleaks 5 findings in selected source were reviewed as
false positives or unchanged reviewed findings. Trivy image HIGH/CRITICAL 0,
secrets 0. Signing inputs were present only in the private build checkout and
excluded from release source, Git, archives and public assets.

Windows/HTTP/database journeys: 26 PASS, 0 failures; 43 HTTP requests, no 5xx.
Covers employee registration, network failure, payment replay, booking, completion,
cancellation/refund, concurrent editing, reopening saved state, native finance
forms and isolated synthetic restore. The compact timeline status assertion was
updated to inspect the visible hovered tooltip instead of removed standalone text.
Full journey rerun PASS after that test-only change.

Windows ZIP and Inno Setup built successfully. APK/AAB version 1.5.32, code 212,
package magic.crm; signatures verified against the existing signing certificate
SHA-256 `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
APK installed on API35 emulator; cold launch and empty-login validation PASS,
crash buffer empty. Android full employee workflows were not rerun on-device;
those ran on Windows against HTTP/DB. AAB JAR signature verification passed with
self-signed certificate/timestamp/ZIP manifest ordering warnings; APK v2 verified.

Two source whitespace-only warnings (extra trailing blank lines in response DTOs)
remain; they have no compilation/runtime effect. No old PASS is used as proof of
new product code. Local evidence is under `dist/release212-final/`.

## Production outcome and artifacts

Guarded cutover PASS. Readiness database/migrations/workers/outbox PASS. Two
commerce reconciliations returned `issues=[]`. Post-release read-only probe:
poison/due/unpublished/dead-letter queues 0; partial miss inactive, partial lesson
active; missing current expense revisions 0 (production currently has 0 expenses).
No production test transactions or manual financial-history rewrites were made.

Published to production downloads and GitHub release v1.5.32:

| Artifact | SHA-256 |
| --- | --- |
| MagicMusicCRM-1.5.32-212-Setup.exe | fcd791c213daedb78479497d04e1550412fa14c1f92471cd1af517d26208e414 |
| MagicMusicCRM-1.5.32-212-windows-x64.zip | 38179cdcf33beb3c8a98e1f729f2b580d87ebb66cce77ccb004dc039e2ad0ca3 |
| MagicMusicCRM-1.5.32-212.apk | b031ad16b0083dde3b884b1ecc139abf5a4faf734354002d983f4499a2668622 |
| MagicMusicCRM-1.5.32-212.aab | ee6583528835d70c8759feee323ef2367480b1df228a4a2b1998b3749f4c988e |

Both public update channels select build 212. The four remote file hashes match
local hashes. GitHub release contains these four files and SHA256SUMS.

## Backup and recovery boundary

Encrypted pre-cutover copy `magicmusiccrm-staging-20260905T201553Z.tgz.enc`, SHA-256
`5a1e918d4d55ce877faf332cbfb965d88165ff733f0cd5559fac444cf1694d4b`.
Post-release copy `magicmusiccrm-staging-20260905T201917Z.tgz.enc`, SHA-256
`8c77365365b4cf49bcd997cc2e21a883cf7846a1f4f54fed78eeaa3e885e4df0`.
Both were copied off-host, checksummed, decrypted only in isolated tooling and
restored/migrated/reconciled to 0154. Private backups are not release assets.

Post-release drill initially failed intermittently during pg_restore. A diagnostic
rerun passed twice. PostgreSQL's container entrypoint starts a temporary socket-only
server and then restarts it. The drill used socket pg_isready, allowing restore to
race initialization. The operational script now waits on 127.0.0.1 TCP; two
consecutive fresh restores PASS. The failure harness requires TCP and supports
both BusyBox and GNU checksum/timeout behavior. This operational follow-up is
separate from the immutable application release commit/image.

The legacy 211 image's migration/read probes pass against the isolated 0154 schema;
this does NOT validate expense-writing compatibility. The deployment guard blocks
rollback to a pre-0151 writer after 0151 is installed, keeping API/Caddy closed on
failure. Recovery requires a compatible forward fix. Never restore an old backup
over new committed business activity or drop append-only financial/audit history.
Clients must update to 212 before editing expenses.

### Operational harness limitation

The full mocked backup failure harness was also run in the local GNU-coreutils
helper. Its success case and 15 injected failure phases passed, including the
new TCP requirement. GNU checksum and timeout return-code differences were fixed
in the test adapter. The suite still fails at `signal-checksum-hup` because its
tracked child does not disappear; adding container init did not resolve it.
Do not label this full signal/cleanup harness PASS. The doubtful assumption is
that its BusyBox-oriented process/signal simulation is portable to this helper.
Further changes to that harness were stopped. This is distinct from the two
successful real encrypted restores and does not change the deployed application.