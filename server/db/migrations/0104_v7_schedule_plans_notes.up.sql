-- v7 T1.1.3: named recurring plans, configurable settlement snapshots and
-- one canonical internal note per client lineage.

create table app.schedule_plans (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  title text not null,
  student_id uuid references app.students(id) on delete restrict,
  group_id uuid references app.groups(id) on delete restrict,
  subscription_id uuid references app.subscriptions(id) on delete restrict,
  active_from date not null,
  active_until date,
  status text not null default 'active',
  version bigint not null default 1,
  ended_at timestamptz,
  ended_by uuid references app.users(id) on delete restrict,
  end_reason text,
  created_by uuid not null references app.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schedule_plans_kind_check check (kind in ('individual', 'group')),
  constraint schedule_plans_title_check
    check (char_length(btrim(title)) between 1 and 160),
  constraint schedule_plans_subject_check
    check (
      (
        kind = 'individual' and student_id is not null and group_id is null
        and subscription_id is not null
      )
      or (
        kind = 'group' and student_id is null and group_id is not null
        and subscription_id is null
      )
    ),
  constraint schedule_plans_active_range_check
    check (active_until is null or active_until >= active_from),
  constraint schedule_plans_status_check check (status in ('active', 'ended')),
  constraint schedule_plans_version_positive check (version > 0),
  constraint schedule_plans_end_shape_check
    check (
      (
        status = 'active' and ended_at is null and ended_by is null
        and end_reason is null
      )
      or (
        status = 'ended' and active_until is not null and ended_at is not null
        and ended_by is not null and nullif(btrim(end_reason), '') is not null
      )
    )
);

create or replace function app.validate_schedule_plan_relations()
returns trigger
language plpgsql
as $$
declare
  subscription_student_id uuid;
begin
  if new.kind = 'individual' then
    select student_id into subscription_student_id
    from app.subscriptions
    where id = new.subscription_id;
    if subscription_student_id is distinct from new.student_id then
      raise exception using
        errcode = '23514',
        constraint = 'schedule_plans_subscription_owner_check',
        message = 'individual plan subscription must belong to its student';
    end if;
  end if;
  return new;
end;
$$;

create trigger schedule_plans_validate_relations
before insert or update on app.schedule_plans
for each row execute function app.validate_schedule_plan_relations();

create index schedule_plans_student_idx
  on app.schedule_plans (student_id, status, active_from desc, id)
  where student_id is not null;
create index schedule_plans_group_idx
  on app.schedule_plans (group_id, status, active_from desc, id)
  where group_id is not null;

create table app.schedule_plan_participants (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references app.schedule_plans(id) on delete restrict,
  student_id uuid not null references app.students(id) on delete restrict,
  subscription_id uuid not null
    references app.subscriptions(id) on delete restrict,
  effective_from date not null,
  effective_until date,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schedule_plan_participants_range_check
    check (effective_until is null or effective_until >= effective_from),
  constraint schedule_plan_participants_version_positive check (version > 0)
);

create or replace function app.validate_schedule_plan_participant()
returns trigger
language plpgsql
as $$
declare
  plan_kind text;
  subscription_student_id uuid;
begin
  perform pg_advisory_xact_lock(
    hashtextextended(new.plan_id::text || ':' || new.student_id::text, 0)
  );
  select kind into plan_kind from app.schedule_plans where id = new.plan_id;
  select student_id into subscription_student_id
  from app.subscriptions where id = new.subscription_id;
  if plan_kind is distinct from 'group' then
    raise exception using
      errcode = '23514',
      constraint = 'schedule_plan_participants_group_plan_check',
      message = 'participants belong only to group plans';
  end if;
  if subscription_student_id is distinct from new.student_id then
    raise exception using
      errcode = '23514',
      constraint = 'schedule_plan_participants_subscription_owner_check',
      message = 'participant subscription must belong to participant';
  end if;
  if exists (
    select 1
    from app.schedule_plan_participants existing
    where existing.plan_id = new.plan_id
      and existing.student_id = new.student_id
      and existing.id <> new.id
      and daterange(
        existing.effective_from,
        coalesce(existing.effective_until, 'infinity'::date),
        '[]'
      ) && daterange(
        new.effective_from,
        coalesce(new.effective_until, 'infinity'::date),
        '[]'
      )
  ) then
    raise exception using
      errcode = '23514',
      constraint = 'schedule_plan_participants_no_overlap',
      message = 'participant effective periods overlap';
  end if;
  return new;
end;
$$;

create trigger schedule_plan_participants_validate
before insert or update on app.schedule_plan_participants
for each row execute function app.validate_schedule_plan_participant();

create index schedule_plan_participants_plan_idx
  on app.schedule_plan_participants
    (plan_id, student_id, effective_from, effective_until, id);

alter table app.schedule_series
  add column if not exists plan_id uuid
    references app.schedule_plans(id) on delete restrict;
create index schedule_series_plan_idx
  on app.schedule_series (plan_id, weekday, begin_time, id)
  where plan_id is not null and deleted_at is null;

alter table app.lesson_client_charge_facts
  drop constraint if exists lesson_client_charge_facts_shape_check,
  add column if not exists settlement_type_key text,
  add column if not exists settlement_label text,
  add column if not exists settlement_color_token text,
  add column if not exists hour_share_basis_points integer,
  add column if not exists fixed_penalty_minor bigint,
  add column if not exists configuration_revision_id uuid
    references app.crm_configuration_revisions(id) on delete restrict;

alter table app.lesson_client_charge_facts
  add constraint lesson_client_charge_facts_v7_snapshot_shape_check
  check (
    (
      settlement_type_key is null and settlement_label is null
      and settlement_color_token is null and hour_share_basis_points is null
      and fixed_penalty_minor is null and configuration_revision_id is null
    )
    or (
      settlement_type_key ~ '^[A-Za-z0-9._:-]{1,120}$'
      and nullif(btrim(settlement_label), '') is not null
      and settlement_color_token ~ '^[A-Za-z0-9._:-]{1,80}$'
      and hour_share_basis_points between 0 and 20000
      and coalesce(fixed_penalty_minor, 0) >= 0
      and configuration_revision_id is not null
    )
  ),
  add constraint lesson_client_charge_facts_shape_check
  check (
    (
      settlement_type_key is null
      and (
        (
          charge_type = 'subscription' and subscription_id is not null
          and amount_minor = 0 and units = snapshot_value
        )
        or (
          charge_type = 'personal_account' and subscription_id is null
          and amount_minor = round(snapshot_value * 100)::bigint and units = 0
        )
        or (
          charge_type = 'none' and subscription_id is null
          and snapshot_value = 0 and amount_minor = 0 and units = 0
        )
      )
    )
    or (
      settlement_type_key is not null
      and (
        (charge_type = 'subscription' and subscription_id is not null)
        or (charge_type in ('personal_account', 'none') and subscription_id is null)
      )
      and snapshot_value >= 0 and amount_minor >= 0 and units >= 0
      and coalesce(fixed_penalty_minor, 0) <= amount_minor
    )
  );

alter table app.lesson_teacher_compensation_facts
  drop constraint if exists lesson_teacher_compensation_facts_type_check,
  drop constraint if exists lesson_teacher_compensation_facts_shape_check,
  add column if not exists compensation_rule_key text,
  add column if not exists compensation_rule_label text,
  add column if not exists compensation_mode text,
  add column if not exists compensation_default_value bigint,
  add column if not exists compensation_actual_value bigint,
  add column if not exists compensation_override_reason text,
  add column if not exists configuration_revision_id uuid
    references app.crm_configuration_revisions(id) on delete restrict;

alter table app.lesson_teacher_compensation_facts
  add constraint lesson_teacher_compensation_facts_type_check
    check (compensation_type in ('none', 'standard', 'percent', 'fixed', 'hourly')),
  add constraint lesson_teacher_compensation_facts_v7_snapshot_shape_check
  check (
    (
      compensation_rule_key is null and compensation_rule_label is null
      and compensation_mode is null and compensation_default_value is null
      and compensation_actual_value is null
      and compensation_override_reason is null
      and configuration_revision_id is null
    )
    or (
      compensation_rule_key ~ '^[A-Za-z0-9._:-]{1,120}$'
      and nullif(btrim(compensation_rule_label), '') is not null
      and compensation_mode in ('none', 'standard', 'percent', 'fixed', 'hourly')
      and compensation_type = compensation_mode
      and compensation_default_value >= 0
      and compensation_actual_value >= 0
      and configuration_revision_id is not null
      and (
        compensation_override_reason is null
        or nullif(btrim(compensation_override_reason), '') is not null
      )
    )
  ),
  add constraint lesson_teacher_compensation_facts_shape_check
  check (
    (
      compensation_rule_key is null
      and (
        (
          compensation_type = 'fixed'
          and rate_minor = round(snapshot_rate * 100)::bigint
          and amount_minor = rate_minor
        )
        or (
          compensation_type = 'hourly'
          and rate_minor = round(snapshot_rate * 100)::bigint
          and amount_minor = round(
            snapshot_rate * 100 * duration_minutes / 60
          )::bigint
        )
        or (
          compensation_type = 'none' and snapshot_rate = 0
          and rate_minor = 0 and amount_minor = 0
        )
      )
    )
    or (
      compensation_rule_key is not null
      and rate_minor = round(snapshot_rate * 100)::bigint
      and (
        (compensation_mode = 'none' and compensation_actual_value = 0 and amount_minor = 0)
        or (
          compensation_mode = 'standard'
          and compensation_actual_value = compensation_default_value
          and rate_minor = compensation_actual_value
          and amount_minor = compensation_actual_value
        )
        or (
          compensation_mode = 'percent'
          and compensation_actual_value between 0 and 20000
          and rate_minor = compensation_default_value
          and amount_minor = round(
            compensation_default_value::numeric * compensation_actual_value / 10000
          )::bigint
        )
        or (
          compensation_mode = 'fixed'
          and rate_minor = compensation_actual_value
          and amount_minor = compensation_actual_value
        )
        or (
          compensation_mode = 'hourly'
          and rate_minor = compensation_actual_value
          and amount_minor = round(
            compensation_actual_value::numeric * duration_minutes / 60
          )::bigint
        )
      )
    )
  );

create table app.client_internal_notes (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid references app.leads(id) on delete restrict,
  student_id uuid references app.students(id) on delete restrict,
  body text not null default '',
  version bigint not null default 1,
  updated_by uuid not null references app.users(id) on delete restrict,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint client_internal_notes_subject_check
    check (lead_id is not null or student_id is not null),
  constraint client_internal_notes_body_length_check
    check (char_length(body) <= 20000),
  constraint client_internal_notes_version_positive check (version > 0)
);

create unique index client_internal_notes_lead_unique_idx
  on app.client_internal_notes (lead_id) where lead_id is not null;
create unique index client_internal_notes_student_unique_idx
  on app.client_internal_notes (student_id) where student_id is not null;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update on app.schedule_plans to magiccrm_app;
    grant select, insert, update on app.schedule_plan_participants to magiccrm_app;
    grant select, insert, update on app.client_internal_notes to magiccrm_app;
  end if;
end $$;
