/** Shared predicate for the `lesson` and `series` aliases.
 * Individually edited occurrences keep their identity, funding and audit history
 * when the recurring template changes or a row is removed.
 */
export const unchangedScheduleLessonSql = `
  lesson.original_scheduled_at is null
  and lesson.predecessor_id is null
  and lesson.teacher_id is not distinct from series.teacher_id
  and lesson.room_id is not distinct from series.room_id
  and lesson.branch_id is not distinct from series.branch_id
  and lesson.duration_minutes = series.duration_minutes
  and lesson.series_date is not null
  and lesson.scheduled_at = (
    (lesson.series_date + series.begin_time) at time zone
    coalesce(series.timezone_name,
      (select timezone_name from app.branches where id = series.branch_id),
      'Europe/Moscow')
  )
  and not exists (
    select 1 from app.lesson_settlement_plans individual_plan
    where individual_plan.lesson_id = lesson.id
      and (individual_plan.version > 1
        or individual_plan.decision is distinct from series.planned_financial_decision)
  )
`;
