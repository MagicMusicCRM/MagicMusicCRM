# SYS-SCHEDULE v7 — L1 Details

## 1. Transition decision input

Rich financial decision replaces booleans:

- `settlementTypeKey`;
- `teacherCompensationRuleKey`;
- optional explicit `teacherCompensationValueMinor` override;
- `reasonText` mandatory for move/cancel/resource change and override;
- group `clientDecisions[]` only when participant subscription differs;
- current `reasonCode` may remain optional classification, never substitutes text.

Preview resolves current effective config and returns its revision, labels/colors,
calculated client units/penalty and teacher amount. Token binds actor, lesson,
version, successor, config revision, subscription/reservation fingerprints and
decisions. Commit compares a newly calculated fingerprint.

Existing automatic completion worker no longer creates terminal financial facts.
When scheduled time passes, it idempotently marks the lesson
`settlement_pending` and emits a staff-queue invalidation. Only the explicit
settle command creates `completed` client/teacher facts. New plan/series snapshots
do not store a teacher-compensation default; legacy values remain display-only
until their lesson is explicitly settled.

## 2. Operation mapping

| User action | Source outcome | Successor | Client settlement | Teacher accrual |
|---|---|---|---|---|
| Normal lesson | completed | none | selected normal/partial/free | explicit selected rule |
| Paid miss | completed | none or optional later lesson | selected charge | selected rule |
| Unpaid miss | completed | none | zero | selected rule, often none |
| Penalty | completed | none | share and/or fixed penalty | selected rule |
| Move with charge | rescheduled | scheduled | source charge | source teacher decision |
| Move without charge | rescheduled | scheduled | zero explicit fact | source teacher decision |
| Teacher/room only | rescheduled/continuation | updated successor | none | none until lesson result |

Successor is a new immutable lesson snapshot. If a charged move also creates a
later normal lesson, preview explicitly states that the later settlement may
charge again.

## 3. Plan schema constraints

`schedule_plans` subject check:

- individual: `student_id != null`, `group_id = null`, subscription required;
- group: `student_id = null`, `group_id != null`, plan subscription null;
- title trimmed 1..160; `active_until >= active_from`; version positive;
- status active/ended and ended metadata all-null or all-present.

`schedule_plan_participants` applies to group only: plan/student/subscription,
effective dates, version; unique non-overlapping active mapping per student.
Subscription must belong to participant, be active and have enough units at
lesson reservation time.

## 4. Create/update plan algorithm

1. Validate subject, plan kind, 1+ rows and subscriptions.
2. Sort/lock subject, teacher, room and subscription keys.
3. Validate every row against constraints and cross-row duplicates.
4. Create plan; call existing series creator for each row with `planId`.
5. Generate lessons using current horizon/unique conflict semantics.
6. Group plans snapshot participants and allocate per-client reservations.
7. Audit/outbox once at plan aggregate plus created series ids.

Effective edit ends old series at `effectiveFrom - 1 day` and creates new series;
past lessons/snapshots do not change.

## 5. End plan algorithm

Preview collects series, future scheduled lessons, active reservations and any
already terminal/rescheduled facts. Commit locks plan/version and series in id
order, sets effective end date, cancels only future scheduled/unsettled lessons
through the same transition boundary with a plan-end reason and zero financial
decision, releases reservations, and writes one aggregate audit. Historical and
terminal lessons remain.

## 6. Tray projection

Tray item: lesson id, local date/time, state, settlement marker, relation marker
(source/successor), teacher and room short labels. It never embeds hidden finance
for forbidden actors. Cursor `(scheduled_at,id)`; default page centres around
today, arrows request previous/next bounded page. Plan history remains accessible
after end.

## 7. Flutter ownership

One `LessonDecisionController` owns draft, preview freshness, submit identity and
errors. Containers only select presentation. `ScheduleDayCanvas`, month/week
views, lesson details and Client Card receive callbacks into this controller;
none call `updateLesson` for protected fields.

One `RecurringSchedulePlanSection` renders desktop/mobile with shared data:
expanded active cards, collapsed ended cards, rows, tray and actions. Preferred
schedule remains a separate preference block and never gates lessons/plans.

## 8. Contract checks

- source method search confirms all date/time/teacher/room writes call transition;
- controller denies protected PATCH payloads even when cast from raw JSON;
- preview and commit calculations byte-equivalent for stable facts;
- direct link/back returns original Month/Week/Day/client tray state;
- all status colors have semantics labels and non-color markers.
