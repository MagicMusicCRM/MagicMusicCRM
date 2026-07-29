insert into v4_reconcile_source_facts (invariant_id, entity_id, fact)
values
  (
    'finance.payment-facts',
    'payment-1',
    '{"kind":"payment","studentId":"student-1","amountMinor":"100000"}'
  ),
  (
    'finance.adjustment-facts',
    'adjustment-1',
    '{"kind":"charge","studentId":"student-1","amountMinor":"-25000"}'
  ),
  (
    'finance.balance-facts',
    'student-1',
    '{"balanceMinor":"75000"}'
  ),
  (
    'commerce.subscription-facts',
    'subscription-1',
    '{"studentId":"student-1","status":"active","snapshotHash":"snapshot-1"}'
  ),
  (
    'schedule.lesson-facts',
    'lesson-1',
    '{"status":"scheduled","teacherId":"teacher-1","branchId":"branch-1","roomId":"room-1"}'
  ),
  (
    'schedule.participation-facts',
    'participation-1',
    '{"lessonId":"lesson-1","studentId":"student-1","attendanceKind":"attended"}'
  ),
  (
    'workflow.task-facts',
    'task-1',
    '{"entityType":"student","entityId":"student-1","status":"open","assigneeId":"staff-1"}'
  ),
  (
    'access.role-mappings',
    'user-1:link-1',
    '{"role":"client","entityType":"student","entityId":"student-1"}'
  );

insert into v4_reconcile_target_facts (invariant_id, entity_id, fact)
select invariant_id, entity_id, fact
from v4_reconcile_source_facts;
