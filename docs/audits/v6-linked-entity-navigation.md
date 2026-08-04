# V6-406 — Linked Entity Navigation

Date: 2026-08-04
Status: PASS

## Delivered

- Lesson details expose typed Student/Lead, Teacher, Room, Group and Branch references with visible hover/focus treatment, semantic link actions and a neutral unavailable state.
- Client Lessons, Tasks, Payments and Subscriptions use the existing `EntityLink` registry instead of local navigation branches.
- Desktop offers explicit current-tab and new-tab actions. Android keeps one chronological stack and uses the canonical app location.
- Lesson links resolve to the production Schedule surface and restore date, mode, branch, teacher, room, client filters, selected column and vertical offset.
- Payment and Subscription links resolve to the canonical client workspace section when the client reference is known. Task links open the exact task timeline and scope the request to its related entity.
- Direct-link focus and filter values survive URI serialization. Missing, archived, deleted and forbidden references are handled by the shared fail-closed navigation policy without exposing the target.
- Top-level CRM section changes replace the tab root, so Back returns to the exact previous drilldown state instead of traversing unrelated lateral tabs.

## Verification

- Full Flutter suite: 586/586 PASS.
- V6 suite: 65/65 PASS.
- Direct Task focus/calendar suite: 4/4 PASS.
- Linked navigation targeted suite: 42/42 PASS.
- Windows 1200 px and Android 412 px lesson-reference affordances: PASS.
- Client workspace role/viewport matrix for Admin, Manager and Director at 360/840/1200 px: PASS.
- Allow, forbidden, missing, archived, deleted and unknown typed-link policy cases: PASS.
- Current-tab, new-tab, compact chronological stack and exact Back restoration: PASS.
- `flutter analyze`: PASS.
- `git diff --check`: PASS.
- `git diff -- server`: empty.

## Deliberate boundary

The task does not introduce a second entity router, tab store or visual component family. It extends the existing V6 typed-link registry, workspace controller and V7 component/tokens so navigation policy remains centralized.
