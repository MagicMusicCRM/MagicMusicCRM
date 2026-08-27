# Campaign-12 Tier 3 — Lane G evidence

- Base: `37667c097e850092dbafaa0480c5e4b64e623025`
- Commit: `d972e2b6840e0eec3d2d3d714d12db05cbac4a33`
- Subject: `refactor(messenger-ui): split chat info dialog owners`
- Branch: `codex/campaign12-chat-info`
- Status: PASS — fresh coverage remains the Campaign-12 global gate.

## Ownership result

| Owner | Health | NLOC | Max CCN |
| --- | ---: | ---: | ---: |
| `chat_info_dialog.dart` | 4.59 raw / 9.65 code-only | 257 | 8 |
| `chat_info_controller.dart` | 9.15 | 208 | 10 |
| `chat_info_models.dart` | 8.44 | 231 | 5 |
| `chat_info_view.dart` | 9.47 | 461 | 8 |
| `chat_info_tabs.dart` | 9.65 | 375 | 5 |
| `chat_info_member_dialogs.dart` | 9.65 | 427 | 8 |

The accepted baseline was health 1.00, 807 NLOC, max CCN 45, and weighted
deficit 5649. The compatibility shell's raw score retains 5.06 points of
historical/coverage penalties; its code-only score is 9.65. Every new owner is
at least 8.44, max CCN is at most 10, and RepoWise reports no god/brain finding.

## Verification

- Required RED: missing `chat_info_models.dart` / undefined
  `ChatHistoryBuckets`; exit 1 before production edits.
- Contract + architecture: 6/6 PASS.
- Existing group removal smoke: 1/1 PASS.
- Restricted analyze: 0 issues.
- Explicit six-owner/two-test format gate: 8 files, 0 changed.
- Invariant search and `git diff --check`: PASS.
- Eight verify-only paths: blob-identical, diff exit 0.
- Generated Flutter registrants: restored to HEAD and excluded.
- Final `repowise update --index-only` plus immediate status under the named
  mutex: indexed SHA exactly `d972e2b6840e0eec3d2d3d714d12db05cbac4a33`.
- Final worktree status: clean.

The plan's broad directory format command has an inherited exception:
`chat_header.dart` and `chat_list_tile.dart` require formatting under the
current SDK. They are outside Lane G, remained blob-identical, and were replaced
with the explicit G target list by integrator ruling.
