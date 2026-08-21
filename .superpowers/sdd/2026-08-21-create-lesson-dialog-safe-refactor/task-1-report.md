# Task 1 — Restore a green date-picker baseline

## Implementation

`CreateLessonDialog._dateButton` now creates a date-only rolling lower bound
at local midnight, 30 days before today. Its `firstDate` is the earlier of
that bound and the existing selected lesson date. `initialDate` remains the
selected date unchanged, so editing an old lesson opens the picker without
changing the lesson's date or time.

The owner-approved inline contract in `create_lesson_dialog.dart:20-24` is
unchanged. No routes, keys, or backend calls changed.

## Files

- Modified: `lib/features/admin/presentation/widgets/create_lesson_dialog.dart`
- Added: `test/features/admin/presentation/widgets/create_lesson_dialog_test.dart`
- Added: `.superpowers/sdd/2026-08-21-create-lesson-dialog-safe-refactor/task-1-report.md`

The new widget test is the smallest real-behaviour harness: it mounts the real
dialog in a `ProviderScope`, supplies the external API dependency through the
existing API provider, taps the real date control, and asserts that the real
Material `DatePickerDialog` opens. Reusing the 1,858-line v4 harness would
duplicate its unrelated setup and make this baseline test coupled to finance,
decision-flow, and save scenarios. The edit fixture deliberately retains the
v4 fixture's edit-path fields (`id`, `version`, `student_id`, `student_name`,
`scheduled_at`, and `duration_minutes`), reducing it only to the fields needed
for this behaviour.

## RED evidence

Command run before modifying production code:

```powershell
flutter test test/features/admin/presentation/widgets/create_lesson_dialog_test.dart
```

Exit code: `1`.

Relevant exact output:

```text
00:00 +0: editing a lesson older than 30 days opens the date picker
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
The following assertion was thrown running a test:
initialDate 2026-07-21 00:00:00.000 must be on or after firstDate 2026-07-22 00:00:00.000.
'package:flutter/src/material/date_picker.dart':
Failed assertion: line 235 pos 5: 'initialDate == null || !initialDate.isBefore(firstDate)'
...
00:02 +0 -1: editing a lesson older than 30 days opens the date picker [E]
00:02 +0 -1: Some tests failed.
```

This is the expected RED failure: the fixture selects a date 31 days in the
past while the old picker passed a date-time lower bound only 30 days back.
Flutter rejected `initialDate < firstDate` before it could open the picker.

## GREEN evidence

Commands run after the production edit:

```powershell
flutter test test/features/admin/presentation/widgets/create_lesson_dialog_test.dart
flutter test test/features/v4/lesson_form_test.dart test/features/admin/create_lesson_student_search_test.dart
```

Exit code: `0` for both commands.

Exact test-result output:

```text
00:00 +0: loading .../test/features/admin/presentation/widgets/create_lesson_dialog_test.dart
00:00 +0: (setUpAll)
00:00 +0: editing a lesson older than 30 days opens the date picker
00:01 +1: (tearDownAll)
00:01 +1: All tests passed!

00:00 +0: loading .../test/features/v4/lesson_form_test.dart
...
00:13 +19: ...: edit проходит общий decision preview и не меняет snapshot
00:14 +20: ...: edit позволяет изменить только оплату преподавателю из основного окна
...
00:16 +24: ...: group lesson открывает перенос без фиктивного клиента
...
00:17 +27: ...: (tearDownAll)
00:17 +27: All tests passed!
```

The second command's existing `create_lesson_student_search_test.dart` prints
two `Error loading subscriptions: FormatException: Commerce student projection
is missing` diagnostic lines from its existing fake; the command nevertheless
completed with all 27 tests passing. This task neither introduced nor changes
that fixture.

## Self-review

- `git diff --check` completed with no whitespace errors.
- The `firstDate` expression uses the requested earlier value and leaves
  `initialDate: _selectedDate` intact.
- The rolling lower bound is date-only (`DateTime(year, month, day - 30)`).
- The regression asserts a visible user result rather than source text or mock
  calls; removing the selected-date exception would make it fail.
- The production diff is limited to the date picker; the test and this report
  are the only additional task files.

## Concerns

- The target dialog is a RepoWise hotspot/bug magnet (12 fixes in six months,
  hotspot score 99%, seven dependents); this task intentionally avoids any
  refactor beyond the required date bound.
- Existing combined-suite diagnostic output about a missing commerce projection
  remains, but it is pre-existing and non-failing.
