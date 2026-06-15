# HolliHop Source Inventory

Date: 2026-06-14

## Scope

This is a read-only inventory for adapting HolliHop CRM data into Magic Music CRM v3. It uses:

- Local archived HolliHop backup: `_archive/backups/hollihop_backup_2026-03-14T15-42-12`
- Existing importer code: `server/src/migration/hollihop-import.ts`
- Existing endpoint research scripts under `_archive/test_scripts/`
- Read-only production PostgreSQL count snapshot from `https://api.phantom-net.ru/`
- User-provided HolliHop screenshots from 2026-06-14

Fresh live HolliHop API calls were not executed in this pass because `HOLLIHOP_AUTH_KEY` is not configured locally or in the production API container. The key must be provided as a transient server-side environment variable before live dry-run/import. It must not be committed, logged, sent to Linear, or embedded in Flutter.

## Local HolliHop Backup Counts

| Source file | Root key | Rows |
|---|---:|---:|
| `offices.json` | `Offices` | 2 |
| `locations.json` | `Locations` | 2 |
| `leadstatuses.json` | `Statuses` | 6 |
| `teachers.json` | `Teachers` | 20 |
| `students.json` | `Students` | 922 |
| `leads.json` | `Leads` | 1,736 |
| `edunits.json` | `EdUnits` | 2,034 |
| `edunitstudents.json` | `EdUnitStudents` | 1,090 |
| `payments.json` | `Payments` | 2,709 |

## Branches And Rooms

Archived branches:

- `Сокол`
- `Спортивная`

Room names inferred from `EdUnits.ScheduleItems`:

| Branch | Rooms observed |
|---|---|
| `Сокол` | `Room 1`, `Room 2 Козодаев`, `Room 3`, `BIG Room 4`, `Room 5`, `Guitar room 6`, `Piano room 7` |
| `Спортивная` | `СПОРТИВНАЯ Room 1`, `СПОРТИВНАЯ Room 2`, `СПОРТИВНАЯ Room 3`, `СПОРТИВНАЯ Room 4`, `СПОРТИВНАЯ Room 5` |

Production DB currently has 4 branches and 24 rooms. This is larger than the single local backup and must be deduplicated by external id/name/branch before any new import.

## Lead Statuses

Archived HolliHop statuses:

| External id | Name | Type |
|---:|---|---|
| 1 | `В процессе` | `regular` |
| 5 | `Пробный Урок` | `regular` |
| 6 | `Звонок после пробного` | `regular` |
| 2 | `Успешный` | `successful` |
| 4 | `Отложенный` | `pending` |
| 3 | `Отказ` | `unsuccessful` |

Production DB currently has 10 lead statuses, including non-HolliHop/default statuses such as `Новый`, `Контакт`, `Переговоры`, `Договор`. The kanban must use imported HolliHop display names and stable ordering, not encoded ids.

## Archived Entity Shapes

### Students

Important fields:

- Identity: `ClientId`, `Id`, `FirstName`, `LastName`, `MiddleName`, `Birthday`, `Gender`
- Lifecycle: `Created`, `Updated`, `StatusId`, `Status`, `AddressDate`, `VisitDateTime`
- Contacts: `Mobile`, `Phone`, `EMail`, `UseMobileBySystem`, `UseEMailBySystem`
- CRM: `Maturity`, `LearningTypes`, `Disciplines`, `OfficesAndCompanies`, `Assignees`, `Agents`, `AdSource`, `Position`, `Address`

Nested fields:

- `Disciplines[]`: `Discipline`, `Level`
- `OfficesAndCompanies[]`: `Id`, `Name`
- `Assignees[]`: `Id`, `FullName`
- `Agents[]`: contact-person fields and relationship marker `WhoIs`

Archived status distribution:

- `Закончил обучение`: 643
- `Занимается`: 232
- empty/none: 36
- `Саморегистрация`: 11

### Leads

Important fields:

- Identity/contact: `Id`, `FirstName`, `LastName`, `MiddleName`, `Birthday`, `Mobile`, `Phone`, `EMail`
- Lifecycle: `Created`, `Updated`, `AddressDate`, `StatusId`, `Status`, `StudentClientId`
- CRM: `Level`, `Discipline`, `LearningType`, `Maturity`, `AdSource`, `OfficesAndCompanies`, `Assignees`, `Agents`

Archived status distribution:

- `Успешный`: 896
- empty/none: 382
- `Пробный Урок`: 320
- `Отказ`: 71
- `В процессе`: 57
- `Отложенный`: 7
- `Звонок после пробного`: 3

### Teachers

Important fields:

- Identity/contact: `Id`, `FirstName`, `LastName`, `MiddleName`, `Birthday`, `Mobile`, `Phone`, `EMail`
- Lifecycle: `Created`, `Fired`, `StatusId`, `Status`
- CRM: `Disciplines`, `Levels`, `Maturities`, `Offices`, `Corporative`

Archived status distribution:

- active or `Работает`: 19
- inactive/fired: 1

### Education Units And Schedules

`EdUnits` carry group/individual lesson units and schedule patterns.

Important fields:

- Unit: `Id`, `Type`, `Name`, `Corporative`, `Discipline`, `Level`, `LearningType`, `Maturity`, `StudentsCount`, `StudyUnitsInRange`, `Vacancies`, `Description`
- Branch: `OfficeOrCompanyId`, `OfficeOrCompanyName`, `OfficeOrCompanyAddress`, `OfficeTimeZone`
- Assignment: `Assignee`
- Schedule patterns: `ScheduleItems[]`

Schedule item fields:

- `Id`, `BeginDate`, `EndDate`, `Weekdays`, `BeginTime`, `EndTime`
- `ClassroomId`, `ClassroomName`
- `Teacher`, `TeacherId`, `TeacherIds`, `Teachers`, `TeacherGenders`, `TeacherPhotoUrls`

Archived schedule facts:

- `ScheduleItems`: 12,268
- date range: 2023-03-18 through 2026-05-31
- dominant weekday masks: one-day weekly masks for each weekday, plus some combined masks

Current importer generates lessons from these schedule patterns, but it does not reliably assign teacher ids to lessons/groups. This blocks teacher schedule views and conflict detection.

### Payments

Important fields:

- Identity: `Id`, `ClientId`, `ClientName`
- Date/state: `Created`, `Date`, `PaidDate`, `RequiredPaidDate`, `State`
- Finance: `Type`, `Value`, `ValueQuantity`, `ValueCurrency`, `PaymentMethodId`, `PaymentMethodName`, `Description`
- Branch: `OfficeOrCompanyId`, `OfficeOrCompanyName`

Archived payment facts:

- Paid: 2,708
- Unpaid: 1
- Methods: mostly `Безналичные`, plus `Наличные`, `Банковская карта`
- Types: mostly `Обучение`, plus `Возврат`

Production DB already has 5,806 payments. Monthly production revenue is populated and must be reused for manager dashboard/reporting.

## Production DB Snapshot

Read-only counts from production API container on 2026-06-14:

| Table | Rows |
|---|---:|
| `app.users` | 1,082 |
| `app.profiles` | 1,118 |
| `app.branches` | 4 |
| `app.rooms` | 24 |
| `app.lead_statuses` | 10 |
| `app.leads` | 3,674 |
| `app.students` | 1,953 |
| `app.teachers` | 46 |
| `app.groups` | 4,292 |
| `app.group_students` | 2,300 |
| `app.lessons` | 35,132 |
| `app.payments` | 5,806 |
| `app.tasks` | 2 |
| `app.entity_comments` | 1 |
| `app.audit_events` | 525 |
| `app.user_crm_links` | 0 |

User/account split:

| Role | `is_app_account` | Count |
|---|---:|---:|
| `admin` | true | 2 |
| `client` | false | 1,024 |
| `client` | true | 29 |
| `manager` | true | 2 |
| `teacher` | false | 22 |
| `teacher` | true | 3 |

Key finding: production already contains imported CRM records, but no CRM links exist yet. The Users screen must continue filtering by `is_app_account=true`; CRM entity screens must read CRM tables separately.

## Existing Importer Coverage

`server/src/migration/hollihop-import.ts` currently imports:

- `GetOffices` -> `app.branches`
- `GetLeadStatuses` -> `app.lead_statuses`
- `GetTeachers` -> `app.users`, `app.profiles`, `app.teachers`
- `GetStudents` -> `app.users`, `app.profiles`, `app.students`
- `GetLeads` -> `app.leads`
- `GetEdUnits` -> `app.groups`, generated `app.rooms`, generated `app.lessons`
- `GetEdUnitStudents` -> `app.group_students`
- `GetPayments` -> paid-only `app.payments`

Current importer gaps:

- No dry-run/report mode.
- No source snapshot table or field-loss report.
- No live endpoint inventory for tasks/history/comments/actions.
- No staff/employees import.
- No duplicate candidate import/computation.
- No normalized contact persons.
- No preferred schedule model.
- No schedule exceptions/attendance/cancellations from live lesson endpoints.
- No teacher assignment on generated lessons/groups despite schedule fields containing teacher data.

## Candidate Live Endpoints To Validate

Archived research scripts reference these endpoints but no saved local result is present:

- `GetSchedule`
- `GetLessons`
- `GetTasks`
- `GetSubscriptions`
- `GetComments`
- `GetStudentLogs`
- `GetSystemLogs`
- `GetHistory`
- `GetCommunications`
- `GetInvoices`
- `GetEdUnitLessons`
- `GetStudentServices`

Before Phase 03 import expansion, run a read-only live inventory with `HOLLIHOP_AUTH_KEY` passed only via transient environment variable.
