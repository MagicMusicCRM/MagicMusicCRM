# Campaign-12 Lane G — ChatInfoDialog split

## Scope and provenance

- Tier 3 base: `37667c097e850092dbafaa0480c5e4b64e623025`.
- Tier A dependency: integrated Messenger split `37e2ee728a658d13ea9ebe624d307468fb4b0883`.
- Tier D dependency: Profile source `e57ad45f` integrated by `dbd19ab6`.
- Source commit: `afea92f51b6e7c537c825e48a100928b39eb24b2`.
- Verify-only paths: blob-identical to the Tier 3 base (`git diff --exit-code` returned `0`).

## RED and characterization evidence

`flutter test test/features/messenger/chat_info_dialog_contract_test.dart`
failed before production edits because `chat_info_models.dart` did not exist and
`ChatHistoryBuckets` was undefined. The final contract suite contains the five
required exact test names and covers manager/teacher access, request order,
history classification, mute rollback, and identity-change stale-state removal.

## Focused lane gate

- Contract + architecture: `6/6 PASS`.
- Existing group removal smoke: `1/1 PASS`.
- Restricted Flutter analyze: `No issues found` across all six production owners.
- Explicit G format gate: `8 files, 0 changed` (six owners plus two tests).
- The broader inherited directory gate still identifies only
  `chat_header.dart` and `chat_list_tile.dart`; those pre-existing files are out
  of Lane G scope and remain blob-identical to the base.
- Invariant `rg`: found the `limit: 100`, 15-second timeout, callback order
  sites, role/system membership keys, and profile-note service calls in the new
  owners.
- `git diff --check`: PASS.

## Structural result

| Owner | NLOC | Imports | Max CCN | Post-index health |
| --- | ---: | ---: | ---: | ---: |
| `chat_info_dialog.dart` | 257 | 11 | 8 | 4.59 raw / 9.65 code-only |
| `chat_info_controller.dart` | 208 | 5 | 10 | 9.15 |
| `chat_info_models.dart` | 231 | 0 | 5 | 8.44 |
| `chat_info_view.dart` | 461 | 5 | 8 | 9.47 |
| `chat_info_tabs.dart` | 375 | 8 | 5 | 9.65 |
| `chat_info_member_dialogs.dart` | 427 | 6 | 8 | 9.65 |

Accepted baseline was health `1.00`, NLOC `807`, max CCN `45`, weighted
deficit `5649`, with `god_class` and `brain_method`. The shell is now lifecycle
and callback orchestration only; all new owners are health `>= 8.44`, max CCN
`<= 10`, and no owner exceeds `500` NLOC. The shell raw score retains `5.06`
points of non-code history/coverage penalties (untested hotspot, ownership loss,
change entropy, co-change scatter, prior defects); removing those penalties
gives code-only health `9.65` and code-weighted deficit `0`. Its raw historical
weighted deficit is `876`, down from `5649`.

The authoritative module-health command ran in-process over the clean source
HEAD `afea92f51b6e7c537c825e48a100928b39eb24b2` after an index update that had
reported that exact SHA; it returned no `god_class` or `brain_method` findings.
During the three-minute health calculation, the shared multi-worktree index was
advanced to `f3282da96b2ff1a3acd653ff6ec84703d0002618` by another lane. This is an
index-provenance race, not a source change. The report-amended commit is followed
by a serialized final update and immediate status capture to restore the index
to Lane G's final exact SHA.
