# HolliHop Field Map

Date: 2026-06-14

## Modeling Rule

`app.users` is a login/account table. HolliHop `Lead`, `Student`, `Teacher`, `Employee/Staff` records are CRM entities. They can exist without an app account.

The link model must be explicit:

- automatic link by confirmed phone/email
- manual manager/admin link
- audited unlink/relink
- visible link state on both Users and CRM cards

## Entity Map

| HolliHop area | Source | Current v3 target | Required target |
|---|---|---|---|
| Филиалы | `GetOffices`, `OfficesAndCompanies` | `app.branches` | Keep; dedupe by external id/name; add import metadata |
| Аудитории | `EdUnits.ScheduleItems.Classroom*` | `app.rooms` inferred | Keep; add external id/source key, branch-safe uniqueness, current availability API |
| Лиды | `GetLeads` | `app.leads` + `custom_data` | Normalize branch/status/source/discipline/level/category/type/goal/responsible/preferred schedule where filter-critical |
| Статусы лидов | `GetLeadStatuses` | `app.lead_statuses` | Keep real HolliHop names/order/type; support processed/deferred/all groups |
| Ученики | `GetStudents` | `app.students` + `profiles` + technical users | Keep CRM entity separate; do not show as app user unless `is_app_account=true` |
| Контактные лица | `Students.Agents`, `Leads.Agents` | Mostly `custom_data` | Add normalized contact table or JSON with indexed phone/email for linking/search |
| Преподаватели | `GetTeachers`, schedule teacher fields | `app.teachers` + profiles/users | Normalize branches, disciplines, levels, maturities/categories, status, rating; link to app account only when registered |
| Сотрудники | Not present in local backup; visible in screenshots | App staff creation only | Add `staff_members`/employee CRM entity and live endpoint discovery |
| Учебные единицы | `GetEdUnits` | `app.groups` | Keep, but distinguish individual/group/corporate units and preserve description/vacancies/study units |
| Ученики в учебных единицах | `GetEdUnitStudents` | `app.group_students` | Keep; preserve status, date/time, weekdays, study minutes/units |
| Занятия/расписание | `EdUnits.ScheduleItems`; candidate `GetSchedule/GetLessons/GetEdUnitLessons` | generated `app.lessons` | Add schedule pattern/source metadata, teacher assignment, room/teacher matrix endpoints, exception/cancellation support |
| Платежи/выручка | `GetPayments` | `app.payments` | Keep; handle paid/unpaid/refund/return semantics, monthly revenue and account history |
| Задачи | candidate `GetTasks` | mostly empty `app.tasks` | Import tasks with priority/type/creator/branch/communication/client filters |
| История/коммуникации | candidate `GetComments/GetHistory/GetCommunications/GetStudentLogs/GetSystemLogs` | `entity_comments` + `audit_events` only for app activity | Add unified timeline/events import and employee action log view |
| Дубли учеников | computed from phones/names/emails or live endpoint if exists | none | Add duplicate candidate workflow: not duplicate, attach, merge |
| Пользовательские поля | unknown live/custom fields | mostly `custom_data` | Preserve raw source and normalize any filter-critical fields |

## Screen Field Map

### Лиды

Required filters and fields:

- search: name, phone, email
- branch
- status and status groups
- discipline, level, category
- added/address date range
- source/ad source
- request type and learning goal
- responsible assignee
- gender, age
- attached-to-student state
- open-task state
- appeal/visit date/time
- preferred schedule
- custom fields and application data

Backend needs:

- `GET /crm/leads/board`
- `GET /crm/leads/search`
- `GET /crm/leads/:id/card`
- `PATCH /crm/leads/:id/status`
- `POST /crm/leads/:id/link-student`

### Ученики

Required filters and fields:

- search: name, phone, email
- branch, status, discipline, level, category
- responsible, source, request type, type, learning goal
- workplace/school, position
- birthday interval, age, gender
- contract state, personal cabinet/app account state
- payment state, blacklist state
- no open tasks, no email
- appeal/visit/preferred schedule/custom fields/application data

Backend needs:

- `GET /crm/students/search`
- `GET /crm/students/:id/card`
- `POST /crm/students`
- `POST /crm/students/:id/invite`
- `POST /crm/students/:id/link-user`

### Сотрудники

Required filters and fields:

- name, phone, email
- branch
- role
- status: `[Нет]`, `Отпуск`, `Работает`
- birthday interval
- authorization/app account state

Backend needs:

- `app.staff_members` or equivalent CRM entity
- `GET /crm/staff`
- `GET /crm/staff/:id/card`
- `POST /crm/staff/:id/link-user`
- role label `Администратор системы`

### Преподаватели

Required filters and fields:

- name, phone, email
- status/work state
- branch
- birthday interval
- discipline, level
- additional params
- columns: disciplines, levels, categories, branches, rating, description

Backend needs:

- normalized teacher capability tables or indexed JSON fields
- teacher schedule/report actions backed by schedule matrix endpoints

### Действия сотрудников

Required filters and fields:

- employee
- branch
- role
- period
- history type
- action, description

Backend needs:

- imported HolliHop history/action events
- app audit events projected to the same read model
- `GET /crm/activity-log`

### Создать ученика

Required data:

- personal name/gender/birthday/branch/status/responsible
- appeal date/source/type/learning goal
- contacts: email/mobile/phone/social
- learning params: discipline/level/category/type
- contact person: name/relation/mobile/email
- personal cabinet/app invitation
- group assignment
- comment

Backend needs:

- create CRM student without app account by default
- send invite via SMTP/OTP when selected
- link accepted app account after verified phone/email

### Дубликаты учеников

Required workflow:

- compute candidate pairs by phone/email/full name and lead-student overlap
- actions: `Не дубликат`, `Прикрепить`, `Слить`
- irreversible merge confirmation
- audit trail

Backend needs:

- `app.duplicate_candidates`
- `app.duplicate_decisions`
- merge/attach endpoints with transaction safety

### Свободные аудитории / текущая ситуация

Required inputs:

- branch
- date
- time

Required outputs:

- room cards with free/busy/soon state
- current lesson or remaining minutes
- upcoming lesson list

Backend needs:

- `GET /crm/rooms/availability`
- room/lesson overlap query with branch/date/time indexes

### Расписание

Required modes:

- day/week/month
- group by room
- group by teacher
- split by rooms
- trial-only
- request mode
- conflict markers

Backend needs:

- `GET /crm/schedule/matrix`
- `GET /crm/schedule/conflicts`
- normalized schedule pattern/source metadata

### Задачи

Required filters:

- responsible
- creator
- branch
- priority
- status/open
- type
- date/time period
- description/comment
- communication method
- client/entity

Backend needs:

- richer `app.tasks` fields
- imported HolliHop task/comment records
- optimistic status endpoint

### Карточка ученика / лида

Required sections:

- profile/sidebar/contact/status
- CRM information
- custom fields
- linked leads/students/users
- lessons and trials
- preferred schedule
- account/payments
- history and tasks

Backend needs:

- card aggregate endpoints to avoid many frontend round trips
- unified timeline endpoint

## UI Architecture Map

Use a single CRM workspace with side panels:

- Main boards: `Лиды`, `Ученики`, `Расписание`, `Задачи`, `Сотрудники`, `Финансы`
- Right side panel: entity card with tabs `Профиль`, `История`, `Задачи`, `Занятия`, `Платежи`, `Связи`
- Dialogs only for short forms and confirmations
- Saved filters and compact filter chips instead of always-open giant forms
