-- v4 T6.1.1: one shared task, dynamic audience, first-close fact and
-- append-only audience-resolution proof.

create table if not exists app.shared_tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text,
  all_day boolean not null,
  start_at timestamptz,
  end_at timestamptz,
  state text not null default 'open',
  linked_entity_type text,
  linked_entity_id uuid,
  version bigint not null default 1,
  created_by uuid references app.users(id) on delete set null,
  origin text not null default 'runtime',
  migration_state text not null default 'runtime',
  legacy_origin_key text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint shared_tasks_title_check
    check (nullif(btrim(title), '') is not null),
  constraint shared_tasks_state_check
    check (state in ('open', 'closed')),
  constraint shared_tasks_version_positive
    check (version > 0),
  constraint shared_tasks_link_shape_check
    check (
      (linked_entity_type is null and linked_entity_id is null)
      or (
        linked_entity_type ~ '^[A-Za-z0-9._:-]{1,80}$'
        and linked_entity_id is not null
      )
    ),
  constraint shared_tasks_origin_check
    check (origin in ('runtime', 'legacy_backfill')),
  constraint shared_tasks_migration_state_check
    check (migration_state in ('runtime', 'exact_merged', 'separate')),
  constraint shared_tasks_schedule_check
    check (
      origin = 'legacy_backfill'
      or (
        (all_day and start_at is not null and end_at is null)
        or (
          not all_day
          and start_at is not null
          and end_at is not null
          and end_at > start_at
        )
      )
    )
);

create index if not exists shared_tasks_state_time_idx
  on app.shared_tasks (state, start_at, id)
  where deleted_at is null;

create table if not exists app.task_audiences (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references app.shared_tasks(id) on delete restrict,
  audience_type text not null,
  target_id uuid,
  created_at timestamptz not null default now(),
  constraint task_audiences_type_check
    check (audience_type in ('user', 'branch', 'allBranches')),
  constraint task_audiences_target_check
    check (
      (audience_type in ('user', 'branch') and target_id is not null)
      or (audience_type = 'allBranches' and target_id is null)
    ),
  unique (task_id, audience_type, target_id)
);

create unique index if not exists task_audiences_all_branches_unique_idx
  on app.task_audiences (task_id, audience_type)
  where audience_type = 'allBranches';
create index if not exists task_audiences_lookup_idx
  on app.task_audiences (audience_type, target_id, task_id);

create table if not exists app.task_closes (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null unique references app.shared_tasks(id) on delete restrict,
  closed_at timestamptz not null default now(),
  closed_by uuid not null references app.users(id) on delete restrict,
  request_id text not null,
  created_at timestamptz not null default now(),
  constraint task_closes_request_check
    check (nullif(btrim(request_id), '') is not null),
  unique (closed_by, request_id)
);

create table if not exists app.shared_task_reminders (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references app.shared_tasks(id) on delete restrict,
  due_at timestamptz not null,
  channel text not null,
  status text not null default 'pending',
  dedupe_key text not null unique,
  attempts integer not null default 0,
  next_attempt_at timestamptz,
  claimed_at timestamptz,
  claimed_by text,
  delivered_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shared_task_reminders_channel_check
    check (channel in ('in_app', 'push', 'email')),
  constraint shared_task_reminders_status_check
    check (status in ('pending', 'claimed', 'delivered', 'cancelled', 'poison')),
  constraint shared_task_reminders_attempts_check
    check (attempts >= 0),
  constraint shared_task_reminders_dedupe_check
    check (nullif(btrim(dedupe_key), '') is not null)
);

create index if not exists shared_task_reminders_due_idx
  on app.shared_task_reminders (
    coalesce(next_attempt_at, due_at),
    id
  )
  where status = 'pending';

create table if not exists app.task_audience_resolution_audits (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references app.shared_tasks(id) on delete restrict,
  action text not null,
  actor_user_id uuid references app.users(id) on delete restrict,
  matched_audience_id uuid references app.task_audiences(id) on delete restrict,
  matched_selector jsonb not null,
  membership_version text,
  membership_at timestamptz not null,
  request_id text,
  created_at timestamptz not null default now(),
  constraint task_audience_resolution_action_check
    check (action in ('list', 'close', 'reminder')),
  constraint task_audience_resolution_selector_check
    check (jsonb_typeof(matched_selector) = 'object')
);

create index if not exists task_audience_resolution_audits_task_idx
  on app.task_audience_resolution_audits (task_id, created_at, id);

create table if not exists app.shared_task_legacy_links (
  legacy_task_id uuid primary key references app.tasks(id) on delete restrict,
  shared_task_id uuid not null references app.shared_tasks(id) on delete restrict,
  merge_proof text not null,
  source_fingerprint text not null,
  created_at timestamptz not null default now(),
  constraint shared_task_legacy_links_proof_check
    check (merge_proof in ('exact_common_origin', 'separate_ambiguous'))
);

create index if not exists shared_task_legacy_links_shared_idx
  on app.shared_task_legacy_links (shared_task_id, legacy_task_id);

create or replace function app.reject_shared_task_append_only_fact()
returns trigger
language plpgsql
as $$
begin
  raise exception using
    errcode = '23514',
    message = TG_TABLE_NAME || ' is append-only';
end;
$$;

drop trigger if exists task_closes_append_only on app.task_closes;
create trigger task_closes_append_only
before update or delete on app.task_closes
for each row execute function app.reject_shared_task_append_only_fact();

drop trigger if exists task_audience_resolution_audits_append_only
  on app.task_audience_resolution_audits;
create trigger task_audience_resolution_audits_append_only
before update or delete on app.task_audience_resolution_audits
for each row execute function app.reject_shared_task_append_only_fact();

create temporary table v4_exact_task_groups
on commit drop
as
with candidates as (
  select
    task.*,
    md5(
      jsonb_build_array(
        task.entity_type::text,
        task.entity_id::text,
        task.title,
        task.description,
        task.status,
        task.due_at,
        task.priority,
        task.due_all_day,
        task.created_by::text,
        task.created_at,
        task.deleted_at
      )::text
    ) as fingerprint
  from app.tasks task
),
proven as (
  select fingerprint
  from candidates
  where assigned_to is not null
    and created_by is not null
  group by fingerprint
  having count(*) > 1
    and count(*) = count(distinct assigned_to)
)
select candidate.*
from candidates candidate
join proven using (fingerprint);

insert into app.shared_tasks (
  title,
  body,
  all_day,
  start_at,
  end_at,
  state,
  linked_entity_type,
  linked_entity_id,
  version,
  created_by,
  origin,
  migration_state,
  legacy_origin_key,
  created_at,
  updated_at,
  deleted_at
)
select
  min(title),
  min(description),
  bool_or(due_all_day),
  min(due_at),
  null,
  case
    when bool_and(status in ('done', 'completed', 'cancelled'))
      then 'closed'
    else 'open'
  end,
  min(entity_type::text),
  min(entity_id::text)::uuid,
  1,
  min(created_by::text)::uuid,
  'legacy_backfill',
  'exact_merged',
  'exact:' || fingerprint,
  min(created_at),
  max(updated_at),
  max(deleted_at)
from v4_exact_task_groups
group by fingerprint
on conflict (legacy_origin_key) do nothing;

insert into app.shared_task_legacy_links (
  legacy_task_id,
  shared_task_id,
  merge_proof,
  source_fingerprint
)
select
  legacy.id,
  shared.id,
  'exact_common_origin',
  legacy.fingerprint
from v4_exact_task_groups legacy
join app.shared_tasks shared
  on shared.legacy_origin_key = 'exact:' || legacy.fingerprint
on conflict (legacy_task_id) do nothing;

insert into app.task_audiences (task_id, audience_type, target_id)
select distinct
  link.shared_task_id,
  'user',
  legacy.assigned_to
from app.shared_task_legacy_links link
join app.tasks legacy on legacy.id = link.legacy_task_id
where link.merge_proof = 'exact_common_origin'
  and legacy.assigned_to is not null
on conflict do nothing;

insert into app.shared_tasks (
  title,
  body,
  all_day,
  start_at,
  end_at,
  state,
  linked_entity_type,
  linked_entity_id,
  version,
  created_by,
  origin,
  migration_state,
  legacy_origin_key,
  created_at,
  updated_at,
  deleted_at
)
select
  task.title,
  task.description,
  task.due_all_day,
  task.due_at,
  null,
  case
    when task.status in ('done', 'completed', 'cancelled')
      then 'closed'
    else 'open'
  end,
  task.entity_type::text,
  task.entity_id,
  1,
  task.created_by,
  'legacy_backfill',
  'separate',
  'legacy:' || task.id::text,
  task.created_at,
  task.updated_at,
  task.deleted_at
from app.tasks task
where not exists (
  select 1
  from app.shared_task_legacy_links link
  where link.legacy_task_id = task.id
)
on conflict (legacy_origin_key) do nothing;

insert into app.shared_task_legacy_links (
  legacy_task_id,
  shared_task_id,
  merge_proof,
  source_fingerprint
)
select
  task.id,
  shared.id,
  'separate_ambiguous',
  md5(
    jsonb_build_array(
      task.entity_type::text,
      task.entity_id::text,
      task.title,
      task.description,
      task.status,
      task.due_at,
      task.priority,
      task.due_all_day,
      task.created_by::text,
      task.created_at,
      task.deleted_at
    )::text
  )
from app.tasks task
join app.shared_tasks shared
  on shared.legacy_origin_key = 'legacy:' || task.id::text
on conflict (legacy_task_id) do nothing;

insert into app.task_audiences (task_id, audience_type, target_id)
select
  link.shared_task_id,
  'user',
  task.assigned_to
from app.shared_task_legacy_links link
join app.tasks task on task.id = link.legacy_task_id
where link.merge_proof = 'separate_ambiguous'
  and task.assigned_to is not null
on conflict do nothing;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update on app.shared_tasks to magiccrm_app;
    grant select, insert, delete on app.task_audiences to magiccrm_app;
    grant select, insert on app.task_closes to magiccrm_app;
    grant select, insert, update on app.shared_task_reminders to magiccrm_app;
    grant select, insert on app.task_audience_resolution_audits to magiccrm_app;
    grant select on app.shared_task_legacy_links to magiccrm_app;
  end if;
end $$;
