# Task 4 implementer report — remove the historical v7 component boundary

## Result

- Moved the eight semantic widget primitives from `lib/core/widgets/v7/` to
  `lib/core/widgets/` without API or body changes, except for required import
  path updates.
- Replaced every live `core/widgets/v7` importer in `lib`, `test`, and
  `integration_test` with direct primitive imports; no aggregate replacement,
  alias, or forwarding export was introduced.
- Deleted `lib/core/widgets/v7/v7.dart` and the empty `v7` directory.
- Removed only the resolved `lib/core/widgets/v7/` naming exception.
- Added the architecture guard that rejects wide historical barrel imports.
  It tolerates git-tracked files that have already been deleted from the
  working tree before staging, so the rule remains runnable during a move.

## RED → GREEN

- RED: `flutter test test/architecture/naming_policy_test.dart` failed as
  intended, listing the existing wide-barrel importers.
- GREEN: the same policy test and the three specified widget test files pass.

## Verification

| Check | Result |
| --- | --- |
| Focused architecture/widget tests | PASS (24 tests) |
| `flutter analyze lib/core/widgets lib/features` | PASS, no issues |
| `dart run tool/check_repository_naming.dart` (staged candidate) | PASS |
| `git diff --cached --check` | PASS |
| `repowise update --index-only` | PASS (already up to date) |
| Sentrux rescan / health / rules / session end | PASS: quality 4889, depth 15, rules PASS, session gate PASS |

## Notes

- The broad historical-path scan has no `core/widgets/v7` or `Shared v7
  component` result. Its `export '.*magic_` branch still matches two
  pre-existing package exports only because the package name is
  `magic_music_crm`; neither exports a widget barrel.
- `dart format --output=none --set-exit-if-changed` reports 61 formatting
  candidates among existing touched sources, including preserved moved widget
  bodies. They were not reformatted: Task 4 requires body preservation and
  prohibits broad formatting. This is the only non-passing diagnostic.
- Sentrux changed from 4890 to 4889 while keeping depth 15 and a passing
  session gate; direct primitive imports increase explicit cross-module edges
  after removing the barrel.
