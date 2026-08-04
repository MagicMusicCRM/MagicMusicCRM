# MagicMusicCRM v6 — Canonical Tasks

**Task:** V6-501 / REQ-TASK-001  
**Status:** PASS  
**Date:** 2026-08-04

## Result

The production task destination, client cards, Lead quick action and Overview now use one `SharedTask` workflow. The legacy `TasksWidget` is not reachable from `main.dart`; its database records remain addressable through `app.shared_task_legacy_links` and resolve to the canonical task.

## Contract

- One create/update/close provider: `/crm/shared-tasks`.
- One task surface per viewport; there is no header action plus duplicate FAB.
- Client-card tasks are filtered by typed Lead/Student link and use the same editor and mutation identity as the main destination.
- A direct task link accepts a canonical or legacy UUID, opens the exact task and its immutable audit history.
- Detail opens through the existing adaptive quick-view policy and exposes the typed linked entity transition.
- Write affordances are fail-closed and use the already loaded capability snapshot; read-only actors do not mount create/edit controls or trigger another access request.
- Overview reads open canonical tasks and no longer queries the legacy provider.

## Evidence

| Gate | Result |
|---|---:|
| Flutter analyze | clean |
| Canonical task/client/navigation targeted tests | 14/14 |
| Full Flutter regression | 590/590 |
| SharedTask PostgreSQL/API/reminder tests | 5/5 |
| Capability route policy with new history endpoint | 41/41 targeted batch |
| Full backend regression | 151/151 suites, 1169/1169 tests |
| Backend typecheck/build | clean |
| V6 inventory | routes 21, reachable files 261, wire calls 261/261, unowned 0 |
| Production legacy task calls | `TasksWidget`/`createTask`/`listTasks` = 0 |

The reachable file count decreased from 264 to 261 because the isolated legacy task implementation and its parallel provider are no longer in the production graph. No dependency or lockfile changed.

## Deferred boundary

Recipient preview, branch/school wording and the complete task language audit belong to V6-502; the canonical persistence and navigation contract required by that work is now stable.
