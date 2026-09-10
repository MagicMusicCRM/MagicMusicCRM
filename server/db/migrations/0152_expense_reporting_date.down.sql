drop materialized view if exists app.mv_finance_monthly;
create materialized view app.mv_finance_monthly as
with bounds as (
  select coalesce(min(date_trunc('month', scheduled_at)), date_trunc('month', now())) as min_month
  from app.lessons where deleted_at is null
),
months as (
  select d::date as month_start
  from bounds, generate_series(bounds.min_month, date_trunc('month', now()), interval '1 month') as d
),
lesson_stats as (
  select date_trunc('month', scheduled_at)::date as m, count(*) as lessons,
         count(*) filter (where status in ('completed', 'done')) as completed
  from app.lessons where deleted_at is null group by 1
),
payment_stats as (
  select date_trunc('month', payment_date)::date as m, sum(amount) as revenue
  from app.payments where deleted_at is null group by 1
),
expense_stats as (
  select date_trunc('month', created_at)::date as m, sum(amount) as expenses
  from app.expenses where deleted_at is null group by 1
),
student_stats as (
  select date_trunc('month', created_at)::date as m, count(*) as new_students
  from app.students where deleted_at is null group by 1
)
select mo.month_start,
       coalesce(ls.lessons, 0) as lessons,
       coalesce(ls.completed, 0) as completed_lessons,
       coalesce(ps.revenue, 0) as revenue,
       coalesce(es.expenses, 0) as expenses,
       coalesce(ss.new_students, 0) as new_students
from months mo
left join lesson_stats ls on ls.m = mo.month_start
left join payment_stats ps on ps.m = mo.month_start
left join expense_stats es on es.m = mo.month_start
left join student_stats ss on ss.m = mo.month_start
order by mo.month_start;
create index if not exists mv_finance_monthly_month_idx on app.mv_finance_monthly (month_start);

do $$ begin
  if exists(select 1 from pg_roles where rolname='magiccrm_app') then
    alter materialized view app.mv_finance_monthly owner to magiccrm_app;
  end if;
end $$;
