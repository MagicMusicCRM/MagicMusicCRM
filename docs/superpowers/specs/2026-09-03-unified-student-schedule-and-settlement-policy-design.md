# Unified Student Lesson Timeline and Settlement Policy

**Status:** approved by the product owner on 2026-09-03

## Context

The client card currently renders one lesson tray inside every recurring
schedule plan. Individually created lessons are used only as a fallback when
the student has no plans. A plan edit replaces the active row projection, so
the UI can make earlier finite periods and their lessons appear to disappear
even though the lesson facts still exist.

Recurring schedule rows can be edited or the whole plan can be ended, but an
operator cannot remove one row and preview what will happen to its future
lessons. One-off changes to a generated lesson, such as another teacher or
room for one date, are not presented beside the schedule rules that produced
the lesson.

Lesson cancellation and rescheduling already have signed preview/commit
commands, optimistic versions, idempotency, transactions, audit/outbox facts,
and subscription reservation handling. These capabilities are not exposed as
one coherent workflow from every lesson entry point. Rescheduled successors
also fall outside the current per-plan tray because successors are independent
lesson facts linked to the source instead of new members of the original
series.

The financial configuration currently treats the client settlement type and
teacher compensation rule as independent selections. Partial settlement types
carry a fixed 50 percent share in configuration. Flutter forms implement
their own defaults, and payroll reports count the full scheduled duration even
when a teacher receives only part of the standard rate. This does not support
the approved business rule that the client charge type should suggest the
teacher rule while still allowing an authorized manual override.

## Product Decisions

1. The client card has one canonical lesson timeline for the student. It
   contains manual lessons, every recurring-plan occurrence, cancellation
   facts, and the current members of reschedule chains.
2. The recurring schedule area presents rule history and one-off exceptions.
   It does not own separate competing lesson feeds.
3. Removing a schedule row affects only future unfinished occurrences.
   Historical, completed, cancelled, deleted, and rescheduled facts remain
   immutable.
4. Cancellation and rescheduling use the existing lesson transition domain.
   No second cancellation status, transfer table, or financial pipeline is
   introduced.
5. One server-owned settlement policy supplies defaults for lesson creation,
   editing, recurring plans, completion, cancellation, rescheduling, and
   corrections.
6. The user-facing configuration block for lesson settlement types and teacher
   compensation rules is removed. Those catalogs become system-owned,
   revisioned policy data. Historical revisions remain readable.

## Canonical Student Lesson Timeline

The schedule backend exposes one keyset-paginated lesson timeline filtered by
student. The implementation may extend the existing lesson query endpoint or
place the projection behind a student-scoped route, but there must be one
query/service implementation and one Flutter controller for this surface.

The timeline reads existing lesson, series, lifecycle, reservation, settlement,
teacher, room, and branch data. It must not add a parallel lesson model or copy
lesson facts into a presentation table unless measured query performance later
requires a cache.

Each timeline item includes:

- the stable lesson id, scheduled time, duration, lifecycle state, and version;
- student/group, teacher, branch, and room display references;
- source plan and source series ids when they exist;
- predecessor and successor ids for reschedule history;
- subscription coverage and effective settlement markers;
- whether the occurrence is manual, generated, or a one-off exception to a
  generated series.

The query deduplicates by lesson id and uses `(scheduled_at, id)` as the stable
cursor. It includes records from all of the student's plans and manual lessons.
The Flutter client no longer merges independent per-plan pages.

The active successor is the actionable member of a reschedule chain. Previous
members remain visible as history with a `Перенесено` marker and a link to the
current successor. A cancelled lesson is red. A covered scheduled lesson keeps
the green subscription marker in both the client card and general calendar.

## Recurring Schedule Rule Timeline

The plan projection exposes current and historical series snapshots rather
than only `currentRows`. It also derives one-off exceptions from lessons linked
to a series when their current date, teacher, room, branch, or duration differs
from the source series snapshot. A rescheduled successor is shown as the
exception for its source occurrence even though the successor is not inserted
back into the series.

Rows are ordered as follows:

1. active open-ended recurring rows;
2. active or upcoming finite rows, nearest effective range first;
3. upcoming one-off exceptions, nearest date first;
4. expired finite rows and past exceptions, newest first.

Past items therefore move below current work without disappearing. Clicking a
recurring row opens the schedule-row editor. Clicking an exception opens the
canonical lesson editor or lesson transition surface.

## Removing a Recurring Schedule Row

The row action is labelled `Удалить строку` and opens a signed impact preview.
The operator chooses an effective date. It defaults to the row start for a
future row and to the local current date for a current row.

The preview reports:

- the row and effective date;
- how many future scheduled occurrences will be cancelled;
- how many subscription reservations will be released;
- immutable occurrences that will remain because they are completed,
  cancelled, rescheduled, deleted, or manually changed;
- conflicts or stale-version conditions that prevent confirmation.

Commit uses the existing versioned schedule-plan mutation. The selected series
is retired from the effective date without a continuation. Future untouched
occurrences are terminalized through the canonical cancellation lifecycle with
system reason `Строка постоянного расписания удалена`, zero client charge, and
zero teacher compensation. Reservations are released and reallocated through
the existing reservation service.

Removing the final active row ends the plan through the existing plan-end
workflow. It does not create an active plan with no rows. Past facts and audit
history are never physically deleted.

## Cancellation

Every actionable lesson quick view exposes `Перенести` and `Отменить занятие`.
Opening a lesson from the calendar or student timeline reaches the same
transition form.

Cancellation defaults to:

- `Неоплачиваемый пропуск` for the client;
- `Не оплачивать` for the teacher;
- no subscription units and no personal-account charge.

An authorized operator may select another allowed settlement type and adjust
the resulting client and teacher values before preview. The cancellation is
terminal at commit time rather than waiting for auto-completion. The released
subscription capacity becomes available to the next eligible existing lesson.
The system does not silently create an extra lesson or extend a subscription.

## Rescheduling

Rescheduling is an explicit move of one occurrence. It does not edit the
recurring rule. Editing this and future occurrences remains a separate
schedule-row action.

The move form starts with the current student/group, payer, subscription,
teacher, branch, room, duration, notes, and planned financial decision. The
operator selects the new date/time and may change the teacher or room. Preview
validates teacher, room, student/group, branch, required fields, subscription
capacity, and the expected lesson version.

Commit performs one atomic transition:

1. the source becomes `rescheduled` with zero client charge and zero teacher
   compensation;
2. one successor is created with `predecessor_id` pointing to the source;
3. the source receives exactly one `successor_id`;
4. the subscription reservation moves to the successor without double use;
5. the successor receives the resolved teacher rate effective for its teacher
   and scheduled date;
6. audit, outbox, notifications, and realtime events are appended once.

A second move operates on the latest active successor and produces a linear
`A -> B -> C` chain. Optimistic versioning and transactional locks prevent
branches. Selecting an earlier source routes the operator to the current
successor.

A completed lesson may be rescheduled only through the existing correction
path. Preview explicitly warns that completed financial facts will be reversed
and replaced. Historical facts remain append-only.

## Settlement Autofill Policy

The system-owned settlement catalog carries enough metadata for the server to
resolve client and teacher defaults. Flutter consumes the resolved recommendation
and never owns a separate mapping table.

| Settlement type | Client result | Teacher result |
| --- | --- | --- |
| `Занятие` | full scheduled duration | full standard rate |
| `Бесплатное занятие` | zero | zero |
| `Оплачиваемый пропуск` | full scheduled duration | full standard rate |
| `Частично оплачиваемое занятие` | operator-entered duration | operator-entered credited duration |
| `Частично оплачиваемый пропуск` | operator-entered duration | operator-entered credited duration |
| `Неоплачиваемый пропуск` | zero | zero |
| `Занятие со штрафом` | unavailable for new decisions | historical display only |

For a new form session, selecting a settlement type applies the recommendation
once. A manual teacher change marks the draft as manual and subsequent field
updates in that form do not silently overwrite it. Reopening an existing lesson
uses its stored resolved decision. A visible `Применить рекомендуемое правило`
action restores the server recommendation.

The stored settlement plan records the configuration revision and whether the
teacher decision was automatic or manually overridden. A manual compensation
override requires a business reason and the existing teacher-compensation
permission. Users without that permission receive the server-resolved value
and cannot smuggle a teacher override through the API.

## Partial Duration Contract

For either partial settlement type, the form requires two independent values:

- client charge duration for each affected participant;
- teacher credited duration once for the lesson.

The public form displays hours and minutes. The command contract sends exact
integer minutes. Client decisions extend the existing per-participant funding
decision with a charge-duration value. The lesson-level financial decision
carries the teacher credited duration.

Both values must be between zero and the scheduled lesson duration. Changing
lesson duration invalidates preview when an entered partial value is now out of
range; values are never silently clamped.

The settlement engine converts client minutes to the existing
`hourShareBasisPoints`/subscription-unit calculation. Personal-account amount
is proportional to the selected client duration. The engine converts teacher
credited minutes to the existing percent-of-standard calculation. It does not
create another payroll compensation type.

Examples for a 60-minute lesson:

- client 30 minutes means `0.50` subscription units or 50 percent of the
  personal-account base price;
- teacher 45 minutes means 75 percent of the standard lesson compensation;
- client and teacher durations may differ;
- boundary values are allowed but preview recommends the clearer full or zero
  settlement type when appropriate.

## Group Lessons

Client settlement remains per participant. Each participant may have a
different payer, funding source, subscription, settlement type, and partial
charge duration.

Teacher compensation is calculated once for the group lesson. It is not
multiplied by participant count and is not inferred from one participant's
absence. When the group lesson is conducted, the planned teacher rule applies.
When the whole group lesson is cancelled, teacher compensation defaults to
zero. A paid or partial absence for one participant changes only that
participant's client fact.

## Recurring Plans and Materialization

A schedule row stores the complete resolved financial decision, including
partial durations and automatic/manual origin. Every generated occurrence
receives the same frozen plan and the configuration revision used by the row.

Editing a row applies the new decision only from the selected effective date.
Existing historical occurrences keep their snapshots and settlement plans.
The materializer creates exact fractional reservations for partial client
durations. Open-ended materialization therefore remains deterministic across
future runs.

If the row duration changes, preview validates all partial durations before any
series is retired or materialized. A failed validation leaves the previous
series and reservations unchanged.

## Teacher Analytics

`Расчёты преподавателей` continues to read effective teacher compensation
facts. For settled lessons, credited hours are derived from the effective
compensation mode and value:

- `none` contributes zero credited hours;
- `standard`, `fixed`, and `hourly` contribute the full lesson duration;
- `percent` contributes lesson duration multiplied by the effective percent.

Partial-duration decisions therefore show the credited duration rather than
the full scheduled duration. Amounts continue to come from immutable effective
facts. The report and export show scheduled duration, credited duration,
compensation type, standard rate, effective amount, and whether the value was
automatic or manually overridden.

## System-owned Configuration

The Flutter configuration workspace no longer renders the entire
`Занятия и оплата преподавателю` catalog editor. This includes settlement
types, shares, penalties, compensation modes, and their ordering.

Hiding the UI is not the authorization boundary. The backend rejects operator
patches to the system-owned settlement and compensation catalog keys. New
policy revisions are published only by controlled application migrations or
release operations. Existing school and branch revisions remain readable so
old lesson facts retain their historical labels and calculations.

`penalty_lesson` is inactive in the new effective revision. It is not deleted,
and historical facts keep their original label and amount.

## Error Contract

Business failures never surface as generic 500 responses:

- stale lesson or plan version: `409` with the current version;
- changed signed preview: `422` and a prompt to recalculate;
- invalid partial duration: `422` identifying client or teacher field;
- insufficient subscription capacity: `422` with the affected payer and
  subscription;
- schedule conflicts: `422` with teacher, room, or client violations;
- unavailable or terminal lesson: `404` or `409` according to the existing
  domain contract.

The Flutter forms keep entered values, display the field-level message, and
offer recalculation when appropriate. Unexpected server faults keep their
request id for diagnostics and are covered by the existing error boundary.

## Existing Data and Reconciliation

Historical completed, cancelled, rescheduled, paid, and audited facts are not
rewritten.

The release produces a dry-run reconciliation for future scheduled lessons and
active schedule rows. Records carrying explicit manual provenance are left
unchanged. Records created under known automatic defaults can be migrated to
the approved policy after preview. Legacy records without enough provenance
are reported separately and require an explicit decision; the migration does
not guess.

Reconciliation verifies reservation totals, effective teacher facts, schedule
plan versions, and the count of future lessons before and after the change.

## Invariants

- One lesson id identifies one immutable scheduling fact at a point in a
  lifecycle; rescheduling creates a linked successor.
- One source lesson has at most one successor, and only the latest successor is
  actionable.
- Subscription reservations never exceed capacity and are not duplicated
  across a reschedule chain.
- A group lesson produces at most one effective teacher compensation fact.
- Manual decisions are never overwritten by later automatic defaults.
- Plan edits and row removal never rewrite terminal or manually changed
  historical lessons.
- Payroll totals equal the sum of effective teacher compensation facts.
- Client-card and calendar settlement markers come from the same effective
  reservation/settlement projection.

## Verification

Backend unit and PostgreSQL integration tests cover:

- every settlement type for 30, 45, 60, and 90-minute lessons;
- subscription and personal-account funding, fractional reservations, and
  insufficient capacity;
- hourly and fixed teacher rates with zero, full, and partial credited time;
- individual and group lessons, participant-specific absences, whole-group
  cancellation, and one teacher fact per group lesson;
- creation, edit, auto-completion, cancellation, rescheduling, completed
  correction, recurring materialization, and row removal;
- stale/tampered previews, idempotent retries, concurrent moves, transaction
  rollback, and typed non-500 domain errors;
- a mixed student timeline containing manual lessons, multiple plans, row
  versions, cancellations, and reschedule successors without duplicates.

Flutter widget and integration tests cover:

- one global timeline on desktop and phone with stable pagination;
- approved ordering of recurring rules and one-off exceptions;
- deletion preview and last-row plan ending;
- cancellation and move entry points from both calendar and client card;
- one-time autofill, preserved manual override, partial-duration validation,
  and restoration of the recommendation;
- per-participant group funding and one lesson-level teacher decision;
- the hidden configuration block and server-side rejection of direct catalog
  edits;
- Russian field-level errors and responsive adaptive surfaces.

The release candidate runs the full Flutter, backend, PostgreSQL integration,
and production release gates because this change crosses schedule, commerce,
payroll, configuration, and client-card projections.

## Rollout and Rollback

Production rollout requires a fresh backup, the reconciliation dry run, a
versioned policy/configuration revision, server deployment, client deployment,
and post-deploy comparison of lesson, reservation, transition, and payroll
totals.

Rollback deploys the prior server/client versions and restores the prior
effective configuration revision for new decisions. Append-only lesson,
settlement, audit, and transition facts created after rollout are reconciled;
they are never deleted or rewritten to simulate rollback.

## Rejected Alternatives

### Merge per-plan trays in Flutter

This leaves pagination races, successor omissions, and duplicate ownership of
the lesson feed. It fixes the screenshot without fixing the data contract.

### Add a schedule-exception table

One-off changes and reschedule links already exist in lesson and lifecycle
facts. A new table would create a second source of truth and synchronization
work.

### Store partial teacher time as a new payroll model

The existing percent-of-standard rule can represent credited duration exactly
enough and already flows through settlement facts, corrections, and analytics.
A parallel compensation model would duplicate those invariants.
