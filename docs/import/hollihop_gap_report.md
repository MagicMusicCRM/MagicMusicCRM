> ⚠️ **УСТАРЕЛО — не опираться на этот документ.** Проверка живого API 16.07.2026
> показала, что описанных здесь методов (`GetComments`, `GetTasks`, `GetHistory`,
> `GetLessons`, `GetSchedule` и ещё 10) **не существует** — все отвечают 404.
> Актуальная инвентаризация: [hollihop_api_probe_2026-07-16.md](hollihop_api_probe_2026-07-16.md).

# HolliHop Adaptation Gap Report

Date: 2026-06-14

## Executive Summary

Magic Music CRM already contains a partial HolliHop import and many CRM widgets, but it is not yet a coherent replacement for HolliHop.

The main gaps are:

1. Domain model blur: app users, students, teachers and staff are still too closely coupled.
2. Import gap: current importer covers basic entities but misses staff, tasks, history, action logs, duplicates, schedule exceptions and several filter-critical fields.
3. API gap: existing list endpoints are too generic for production-size boards and schedules.
4. UX gap: several CRM widgets exist but are not fully integrated into a single manager workspace, and loading/optimistic states are incomplete.
5. Data QA gap: production already has imported data, but `user_crm_links` is empty and there is no import batch/field-loss reporting.

## P0 Gaps

### P0.1 Users vs CRM Entities

Production currently has many technical imported users:

- `client`, `is_app_account=false`: 1,024
- `teacher`, `is_app_account=false`: 22

These must remain hidden from the Users section. Students, leads, teachers and staff must be shown in CRM sections, not in app-user administration.

Required:

- keep `/admin/profiles` filtered by `is_app_account=true`
- extend explicit CRM linking beyond `student/lead`
- add visible link status and manual link flow

### P0.2 System Admin Role

The current DB enum has only:

- `client`
- `teacher`
- `manager`
- `admin`

Required:

- add a high-privilege role surfaced as `Администратор системы`
- seed/upsert `Садуакасова Уалихана Алимжановича` / `kvazar2727@gmail.com`
- prevent managers from assigning high-privilege roles

### P0.3 Import Safety

Current `hollihop-import.ts` imports directly and has no:

- dry-run mode
- import batch table
- source snapshot/checksum
- field-loss report
- duplicate report
- rollback plan

Required before new live import:

- transient `HOLLIHOP_AUTH_KEY` env setup
- read-only endpoint inventory
- backup
- dry-run report
- manual review

### P0.4 Schedule Correctness

Current importer generates lessons from `EdUnits.ScheduleItems`, but teacher ids are not reliably assigned. This blocks:

- teacher schedule
- teacher conflict detection
- room/teacher matrix accuracy
- "current situation" room view

Required:

- normalize schedule source metadata
- assign teacher/room/branch consistently
- validate live `GetSchedule`, `GetLessons`, `GetEdUnitLessons`

## P1 Gaps

### P1.1 Staff/Employees

Screenshots show staff management and employee actions, but current backend has only app-account staff creation. There is no normalized staff CRM entity independent of app users.

Required:

- `staff_members` or equivalent
- branch/role/status/contact/authorization filters
- link to app account when registered
- activity log projection

### P1.2 Tasks And History

Production has only 2 tasks and 1 entity comment, while HolliHop screenshots show tasks/history as core CRM workflows.

Required:

- live endpoint validation: `GetTasks`, `GetComments`, `GetHistory`, `GetCommunications`, `GetStudentLogs`, `GetSystemLogs`
- unified timeline model
- imported task fields: priority, type, creator, responsible, branch, due date/time, communication method

### P1.3 Rich Filters

Current `CrmListQuery` supports only a small set: `q`, `studentId`, `teacherId`, `branchId`, `status`, `limit`.

Required filters for production boards:

- leads: status/source/responsible/branch/date/type/goal/discipline/level/category/open tasks/preferred schedule
- students: status/branch/group/discipline/category/payment/account/blacklist/no email/no open tasks/date ranges
- tasks: responsible/creator/branch/priority/type/status/date/communication/entity
- schedules: branch/room/teacher/date range/time range/status/trial/request mode

### P1.4 Duplicate Workflow

Local backup analysis found many shared phone candidates across student/lead records. There is no workflow for:

- not duplicate
- attach
- merge
- audit irreversible decisions

Required:

- candidate computation by normalized phone/email/full name
- safe attach and merge transactions
- review UI

### P1.5 Loading And Optimistic UI

Existing skeletons are not applied broadly. Current CRM surfaces still rely on spinners/full reloads and sometimes silent waits.

Required:

- no black cold start
- skeletons for boards, tables, timelines, cards, schedules
- in-flight/disabled state for submit buttons
- optimistic updates with rollback for messages, tasks, lead status moves, comments, role/link changes

## P2 Gaps

### P2.1 Manager Dashboard

The current summary is too sparse and visually oversized. It must become an operational dashboard:

- revenue by month
- expected payments/debts
- active students
- new leads/conversion
- trial outcomes
- schedule conflicts
- room load
- staff activity

### P2.2 UI Navigation

Do not clone HolliHop's many windows. Use:

- one CRM workspace
- boards/tables for scanning
- side panels for entity details
- tabs inside cards for profile/history/tasks/lessons/payments/links

### P2.3 Localization

All user-facing UI must stay Russian. Role labels, system chat names, empty states, errors and loading states must not contain English.

## Recommended Execution Order

1. Configure safe live HolliHop read-only env and run endpoint inventory.
2. Add import batch/dry-run/reporting infrastructure.
3. Fix identity/schema foundation: staff entity, `system_admin`, extended links.
4. Expand import and normalize filter-critical fields.
5. Add board/card APIs for leads/students/tasks/schedule.
6. Add loading/skeleton/optimistic UI foundation.
7. Build CRM workspace screens and side panels.
8. Run staging import with QA report and Android/Windows smoke.

## Acceptance Criteria For Phase 01

Completed in this pass:

- Current local backup counts documented.
- Production DB counts documented.
- Existing importer coverage documented.
- Screenshot-driven field map documented.
- Backend/frontend explorer findings incorporated.
- Security constraint documented: no key persisted or logged.

Remaining before Phase 03 live import:

- Set `HOLLIHOP_AUTH_KEY` as transient env outside the repo.
- Run live endpoint inventory against candidate endpoints.
- Compare live counts with production DB and archived backups.
