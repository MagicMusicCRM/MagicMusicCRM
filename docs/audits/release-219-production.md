# Production release 1.5.39+219

Published with explicit owner authorization on 2026-09-10. Server before client channels.

## Identity and scope

- Tag v1.5.39; revision 2f37c7aee4633a463ba8fad3e322e0d945e50a23; selected build source SHA-256 7509a51a758498fdd814c6d91297ced6d405f92d70488899fbde407761fe29c0; 2198 selected files and 17 explicit working-tree overrides. Snapshot C:/Users/Alinka/mm219publish.
- Candidate magicmusiccrm-server:1.5.39-219-final; ID sha256:f9d80b7831895395376777d83a0b7b1d609140bb0dff0d9614d7673b3bba6bf0; archive SHA-256 2e8ad171464302abba830f6124b7a24093dfbd063405df01dddc561e02defa9f.
- Operations /opt/magicmusiccrm/releases/1.5.39-219-2f37c7ae/; evidence dist/release219/. Schema remains0155_schedule_plan_archive.
- Production218 runtime is retained plus archive restoration and stable plan pagination. Unrelated working-tree changes to API-contract tooling, test runners and accessibility inventory are excluded.

Paginated individual plans and rule records keep a bounded, text-scale-aware viewport. Switching between three records and a short last page, or opening a record, does not move the outer client card or pagination controls. Each page contains at most three records; expanded content scrolls within its viewport.

Archived individual plans expose Restore from archive. Preview, explicit confirmation and a mandatory reason precede a versioned, idempotent transaction with backend capability/branch scope. Only lessons hidden by that plan archive timestamp are revealed. The plan remains ended; lessons stay cancelled, generation does not resume. End reason, financial facts and previous archive audit remain intact; restore appends its own Russian-labelled audit and change event. Stale previews and foreign branches are rejected. New restore endpoints use the existing controller/service/provider flow and add no migration.

## Verification

- Flutter full final run: 1752 tests passed; lib/test/integration_test analyzer clean. Backend 315 suites / 4115 cases validated, zero unresolved failures or skips. Full run plus complete failed suites re-run after restoring unchanged baseline documentation fixtures.
- Initial isolated-checkout failures were environmental: two naming tests needed Git metadata; one backend contract test needed its unchanged baseline docs/contracts JSON. Canonical Git metadata and baseline documentation fixtures were restored into the snapshot, without application changes. Flutter was rerun in full; the failed backend suite was rerun completely on a fresh database. Original and retry logs, source identity and merged case-level evidence are retained. supplemental-git-files.json lists the unchanged baseline supporting files.
- Existing employee Windows/HTTP/PostgreSQL release journeys: 26 passed, 43 requests, zero server errors. Journey runtime/migrations/assets/integration tests were SHA-256 matched between the working checkout and release snapshot; builds used separate trees. New restoration UI and PostgreSQL tests cover missing reason, retry identity, concurrent duplicate requests, stale commands, branch access, restored visibility and unchanged cancellation/financial facts.
- Strict security 11 PASS; wire contracts, deployment/schema/behavior/backup contracts and Bash syntax passed. Exact-image production-config rejection, healthy readiness and degraded503 checks passed.
- Gitleaks: five reviewed unchanged synthetic/public findings, no confirmed secrets. Semgrep findings reviewed against218; no confirmed vulnerabilities. Existing Bash heredoc partial parsing remains covered by native syntax and behavior contracts. Trivy: zero HIGH/CRITICAL vulnerabilities and secrets.
- Windows Release/Setup/ZIP version1.5.39+219; APK/AAB signature verification with unchanged certificate. API35 signed APK cold launch, both login validation messages and empty crash buffer passed. Existing SDK/font/CMake/linker/self-signed certificate warnings are preserved in logs.

## Recovery and data

Pre-cutover backup magicmusiccrm-staging-20260910T172754Z.tgz.enc; SHA-256 a68f250288a143a09c7990e134449450a39ee06f9200e66c6a3c92ade3cbecf6.
Post-release backup magicmusiccrm-staging-20260910T174509Z.tgz.enc; SHA-256 3e8a013a6ef50c9e12678d029699c584ac08cd4222950b65d040e1161319b091.
Both fresh encrypted archives were copied off-host, checksum checked and restored in isolation with candidate and rollback; migration/reconciliation/schema probes passed.

Rollback is stock magicmusiccrm-server:1.5.38-218-final, revision078b32e6f48b0396633188df355716a5427c3f5e, image sha256:b7147997a79354aeec526a6ab8d11a4de2a4659c2ae01204864dba081ff79be8. It supports the unchanged schema and restored ended/cancelled state. Restore endpoints become temporarily unavailable in rollback; prefer forward fix after client publication. Never rewind DB or remove financial/audit history. Previous manifests can halt future upgrades but cannot downgrade installed clients.

Production reconciliation issues=[]. Coverage preview 1 active subscriptions, 0 changes, 0 review-required lessons. No manual apply was needed. Pre/post financial fact counts and SHA-256 match at the same cutoff; environment hash and OTP exception remain unchanged. No user series was restored automatically during deployment.

## Publication

https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.39

Both update channels select219. Public downloads were streamed and SHA-256 verified; GitHub asset digests and source tag match:

- MagicMusicCRM-1.5.39-219-Setup.exe: ba99710b3086055ae10fc45b1d5bf0798ede6a38fdcb0aacd58b3f104adce41c
- MagicMusicCRM-1.5.39-219-windows-x64.zip: 88f1fcd7ebf298c6d7eb828454fe02bd0855f236b7643771dc1ca4c9aab4584b
- MagicMusicCRM-1.5.39-219.apk: 870c4c48167b2ac57bfa1789273b37054ffdd45d82b3f76665c1480dae1641a5
- MagicMusicCRM-1.5.39-219.aab: 5e374ae2bc9820328f65c9286acc1cdde31a1d40fcaffad834502d8d70719652

Working branch and normal index preserved using isolated candidate/evidence indexes. No new user Windows application session launched.
