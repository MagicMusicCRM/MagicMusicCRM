# V6-405 — Configurable Student Funnel

Date: 2026-08-04
Status: PASS

## Delivered

- The primary `Ученики` section now creates a Student through the same canonical form and `POST /crm/students` path as the legacy Management entry.
- The board, create form and Student card consume one effective funnel projection instead of maintaining separate hard-coded status lists.
- Director/system administrator can configure stage labels, named color styles, order, activity and allowed transitions at school or branch scope.
- A branch revision stores only a sparse override over the current school revision. School changes remain inherited unless the branch explicitly overrides the affected stage.
- Existing stage keys are stable: they can be archived but not deleted. Unknown legacy values remain visible in a non-droppable `Требуют сопоставления` column instead of disappearing.
- Publish and rollback are immutable revision operations with expected-version protection, mandatory reason, audit and realtime invalidation.
- Create, edit and drag-and-drop validate the effective target stage server-side in the same transaction as the Student write. The client also disables forbidden transitions and rolls an optimistic move back on rejection.
- Mobile configuration and creation use full-width expandable sheets; desktop uses the existing drawer pattern. Drafts survive network errors, and dirty scope changes or close actions require confirmation.
- The board retains explicit horizontal/vertical desktop scrollbars and keeps configured empty columns visible.

## Scope and access

- Effective read follows the existing actor and branch scope policy.
- Teacher can consume safe stage labels for assigned workflows but receives no school/branch remediation counts.
- Funnel revisions and publish/rollback require Director/system administrator configuration authority; Manager and Admin cannot mutate the configuration.
- School configuration is the default. Branch configuration is a sparse override and never copies an entire school snapshot into branch ownership.
- Branch-first publishing is serialized by an advisory transaction lock. Rollback reapplies the historical sparse patch to the current school configuration, so later school stages are preserved and shown archived when necessary.
- Config access delegation is intentionally not duplicated here; it remains owned by V6-506.

## Data and wire contracts

- Migration `0096_student_funnel_configuration` adds immutable, versioned school/branch revisions and seeds the former statuses as editable school defaults.
- `GET /crm/student-funnel/effective` returns the effective projection and explicit remediation values.
- Revision history, publish and rollback use the same service and capability-route policy as the Flutter editor.
- Student create/update calls the shared funnel validator; there is no UI-only integrity rule.
- The obsolete `CreateStudentDialog` wrapper was removed rather than preserving a second creation implementation.
- The calendar-sensitive lesson-series fixture was changed from fixed August 2026 dates to the next three PostgreSQL-derived Mondays. This is a test-only stability repair; production scheduling behavior is unchanged.

## Verification

- `flutter analyze`: PASS.
- Funnel/service/controller/route-policy targeted backend tests: 68/68 PASS.
- Authorization, funnel and lesson-series regression: 10/10 PASS.
- Full Flutter suite: 580/580 PASS.
- Backend typecheck/build: PASS.
- Full backend suite: 151/151 suites and 1169/1169 tests PASS.
- Responsive board/editor/create coverage: 360/840/1200 px PASS.
- Publish, sparse branch override, inheritance, rollback, archived-stage rejection, transition validation, Manager denial, Teacher count redaction and database immutability: PASS.
- `git diff --check`: PASS.
