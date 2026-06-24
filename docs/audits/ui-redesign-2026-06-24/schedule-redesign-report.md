# Schedule Redesign — Implementation Report (P2 / KVA-195)

**Date:** 2026-06-24 · **Branch:** `kvazar2727/leads-to-students-dnd` · **Type:** frontend reskin (no `server/` changes)

## Files changed
- **NEW** `lib/features/admin/presentation/widgets/schedule_day_canvas.dart` — `ScheduleDayCanvas`, the 2-axis day grid.
- **NEW** `lib/features/admin/presentation/widgets/quick_lesson_sheet.dart` — compact «Назначить занятие» popover.
- **MOD** `lib/features/admin/presentation/widgets/schedule_widget.dart` — Год/Месяц/День switcher, reskinned Month + side summary, new Year view, optimistic move/undo + resize commit. Data layer, conflict/focus/realtime, details dialog and create-dialog wiring preserved.
- **MOD** `test/features/s8_desktop_ux_states_test.dart` — weekday headers `ПН/ВС` → `Пн/Вс` (redesign).
- **NEW** `test/features/admin/schedule_redesign_test.dart` — switcher, month→day, day legend, quick-create popover.
- **MOD** `pubspec.yaml` — build number `125 → 126` (keeps the prior DnD `-125` artifacts intact).

## UX implemented (vs. the PNG spec)
- **Год** — 12-month overview cards with per-month load heatmap + count badge + «Сводка года»; click month → Месяц. Counts/active-days are server-derived from a full-year `getScheduleMonthSummary`; per-month conflicts are **not** fabricated (the summary endpoint doesn't return them).
- **Месяц** — big calendar grid (weekday headers, day cells with count badge + up to 2 type-colored lesson chips + footer), side day-summary panel on wide layouts; click day → День. Uses `getScheduleMonthSummary`.
- **День** — scrollable canvas 08:00→00:00, **wide** time gutter + **narrow fixed-width** room columns, sticky gutter + sticky room headers, both-axis scroll. Interaction legend above the grid (no per-cell instructions).
  - Tap empty hour → 1h quick-create popover; vertical drag-select → multi-hour quick-create (dashed teal block + duration). Horizontal range is **blocked** (red «Горизонтально нельзя» hint).
  - Existing-lesson drag: source stays **highlighted** (no dashed targets), card follows pointer, vertical = time / horizontal = room.
  - Resize handles on **hover** (desktop) **or double-tap** (touch), vertical only (top = start, bottom = duration), commit on release; never opens the editor.
  - Edge autoscroll (X & Y) during a move; vertical-only autoscroll during a select.
  - Optimistic move with **rollback on API error** + **Undo** snackbar (undo offered only when the room change is reversible — clearing a room to «Без аудитории» isn't expressible via the PATCH contract).
- Loading/empty/error transparency (S8) preserved; conflicts/pending states visible.

## API contract — unchanged
- Booking still emits `POST /crm/lessons` with `{scheduledAt(UTC), durationMinutes, one-of student/group, teacherId, roomId, branchId, status}` (both the quick popover and the full dialog).
- Reschedule/resize/move use `PATCH /crm/lessons/:id` (`scheduledAt`, `roomId`, `durationMinutes`). No new endpoints. Conflicts remain server-derived via `GET /crm/schedule/matrix` (`conflict_types`). Year/Month read via `GET /crm/schedule/month-summary`.
- Local→UTC inverse on every write: `utc = DateTime.utc(localFields) − branchOffsetMinutes` (mirror of the grid's `_parseLessonTime`).

## Adversarial review → fixes applied
A 5-dimension multi-agent review (time/UTC, API-contract, gesture/scroll, optimistic-state, spec-compliance) confirmed 6 high findings; all fixed:
1. Top-edge resize clamp drifted the lesson END → duration now derived from the clamped start against the fixed original end.
2. Edge autoscroll didn't run during the vertical drag-select → select now arms `_dragging` (vertical-only).
3/4. «Без аудитории» room-clear was un-expressible via the contract → the unassigned column now rejects roomed-lesson drops; undo is offered only when the room change is reversible (no silently-dropped `roomId:null`).
5. Resize handles were mouse-hover-only → added a double-tap touch reveal (auto-clearing).
6. Move source was dimmed → now stays gold-highlighted in place (rule 7).
Also: realtime refetch now gated by the in-flight move guard.

## Verification
- `flutter analyze` → **No issues found**.
- `flutter test` → **184/184 pass** (incl. unchanged KVA-166 `schedule_day_view_test.dart`, updated `s8_desktop_ux_states_test.dart`, new `schedule_redesign_test.dart`).
- `git diff -- server` → **empty** (before == after, both 0 bytes; patches saved alongside this report).

## Release artifacts (version 1.1.22+126)
| Artifact | Path | SHA-256 |
|---|---|---|
| Windows x64 | `dist/MagicMusicCRM-1.1.22-126-windows-x64.zip` | `5E5B0BE99D757E539DAB761FAE4AD3004031710AD2EA0BC2D16940EAB76B44A5` |
| Android APK | `dist/MagicMusicCRM-1.1.22-126.apk` | `6573D6F2284E581C92EE6E1278F92A0291940C06B2F289E215D7505472D88841` |
| Android AAB | `dist/MagicMusicCRM-1.1.22-126.aab` | `1F5763769A81338B214CDF31D034055DC6407F763D7CB080D9FE794D7F3B05FF` |

All built with `--dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api`.

## Remaining limitations
- **Live GUI visual QA** (running the desktop/mobile app against a seeded backend) was not performed in this environment — it needs an authenticated session. Interactions are covered by the widget tests + adversarial code review; on-device owner acceptance is the remaining gate (matches the project's INT-acceptance pattern).
- **Year-view per-month conflicts** are not shown as exact counts (the `month-summary` endpoint returns only `{day, count, room_ids}`); a backend addition would be required to surface them without fabrication.
- **Touch resize** uses double-tap-to-reveal (no pointer hover on touch); a dedicated long-press would conflict with move-drag.
