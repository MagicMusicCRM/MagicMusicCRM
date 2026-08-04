# V6-403 — Client Month/Week/Day calendar

Date: 2026-08-04  
Status: PASS

## Delivered

- The canonical Lead/Student `Занятия` section now contains one adaptive Month/Week/Day calendar and a concrete accessible-branch selector.
- Every load is bounded to the visible branch-local viewport and a hard limit of 500 rows. Hidden tab content does not prefetch.
- The existing `/crm/schedule/matrix` path is reused twice per viewport: one actor-scoped branch projection for visible lessons and one typed Lead/Student filter for authoritative relation, including group lessons. No names are used as identity.
- Lessons of the client in the open card use the success relation surface and a person marker; other actor-visible lessons use a neutral surface and people marker.
- Lifecycle, trial and conflict remain independent signals with distinct icons/tooltips. A non-color legend explains every relation/exception marker.
- Branch UTC offset is applied to request boundaries and displayed lesson times.
- Loading, retry, empty-branch, forbidden and 500-row truncation states are explicit.
- Day/Week fit the complete 06:00–23:00 range into the calendar viewport; period arrows replace a hidden nested desktop scrollbar.
- Desktop lesson links push a typed Lesson entity with the complete source `ContextViewState`; workspace Back restores mode/date/branch.
- Compact lesson links push the role schedule and retain the client card underneath, so Android system/app Back returns to the same calendar state.
- Direct client URLs persist `section`, `calendarMode`, `calendarDate` and `branchId`.

## Contract evidence

- Existing `GET /crm/schedule/matrix` is unchanged; generated wire baseline is byte-identical.
- No new backend endpoint, domain or dependency was added.
- `git diff -- server` is empty.

## Verification

- `flutter analyze`: PASS.
- Calendar widget/logic/platform suite: 8/8 PASS.
- Calendar + canonical client workspace: 23/23 PASS.
- Full Flutter suite: 568/568 PASS.
- Android 15 API 35 integration drilldown: 1/1 PASS.
- Windows runner integration drilldown: 1/1 PASS.
- UX inventory: 21 routes, 263 production-reachable Dart files, 2 production workspace hosts, 0 unowned.
- `git diff --check`: PASS.
