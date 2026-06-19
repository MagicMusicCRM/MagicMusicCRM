-- server/db/migrations/0031_analytics.up.sql
-- Analytics substrate: refresh-run log + finance materialized views (owned by
-- magiccrm_app so the app-role refresh worker can REFRESH them).

create table if not exists app.analytics_refresh_runs (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  status text not null default 'running',
  claimed_at timestamptz not null default now(),
  ran_at timestamptz,
  finished_at timestamptz,
  error text,
  constraint analytics_refresh_runs_status_check check (status in ('running', 'completed', 'failed'))
);
create index if not exists analytics_refresh_runs_kind_idx
  on app.analytics_refresh_runs (kind, finished_at desc);

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

drop materialized view if exists app.mv_teacher_performance;
create materialized view app.mv_teacher_performance as
select l.teacher_id,
       btrim(concat_ws(' ', tp.first_name, tp.last_name)) as teacher_name,
       count(*) filter (where l.status in ('completed', 'done')) as completed_lessons,
       coalesce(sum(g.price_per_lesson) filter (where l.status in ('completed', 'done')), 0) as revenue
from app.lessons l
left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
left join app.groups g on g.id = l.group_id and g.deleted_at is null
where l.deleted_at is null and l.teacher_id is not null
group by l.teacher_id, tp.first_name, tp.last_name;
create index if not exists mv_teacher_performance_teacher_idx on app.mv_teacher_performance (teacher_id);

drop materialized view if exists app.mv_room_load;
create materialized view app.mv_room_load as
select l.room_id, r.name as room_name, count(*) as lessons
from app.lessons l
left join app.rooms r on r.id = l.room_id and r.deleted_at is null
where l.deleted_at is null and l.room_id is not null
group by l.room_id, r.name;
create index if not exists mv_room_load_room_idx on app.mv_room_load (room_id);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.analytics_refresh_runs to magiccrm_app;
    alter materialized view app.mv_finance_monthly owner to magiccrm_app;
    alter materialized view app.mv_teacher_performance owner to magiccrm_app;
    alter materialized view app.mv_room_load owner to magiccrm_app;
  end if;
end $$;
