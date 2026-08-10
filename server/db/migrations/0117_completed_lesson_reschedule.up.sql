-- Owner correction flow: a completed lesson may be rescheduled exactly once,
-- but only after an append-only zero-effect correction and successor creation.

alter table app.lesson_transitions
  drop constraint if exists lesson_transitions_state_check;

alter table app.lesson_transitions
  add constraint lesson_transitions_state_check
  check (
    (
      from_state in ('scheduled', 'settlement_pending')
      and to_state in ('successfully_completed', 'cancelled', 'rescheduled')
    )
    or (
      from_state = 'successfully_completed'
      and to_state = 'rescheduled'
    )
  );

drop index if exists app.lesson_transitions_one_terminal_idx;
create unique index if not exists lesson_transitions_one_initial_terminal_idx
  on app.lesson_transitions (lesson_id)
  where from_state in ('scheduled', 'settlement_pending');
create unique index if not exists lesson_transitions_one_completed_reschedule_idx
  on app.lesson_transitions (lesson_id)
  where from_state = 'successfully_completed' and to_state = 'rescheduled';

create or replace function app.sync_lesson_lifecycle()
returns trigger
language plpgsql
as $$
declare
  mapped_state text;
begin
  if TG_OP = 'INSERT' then
    new.lifecycle_state := case lower(btrim(new.status))
      when 'settlement_pending' then 'settlement_pending'
      when 'completed' then 'successfully_completed'
      when 'successfully_completed' then 'successfully_completed'
      when 'cancelled' then 'cancelled'
      when 'canceled' then 'cancelled'
      when 'rescheduled' then 'rescheduled'
      else 'scheduled'
    end;
    return new;
  end if;

  if new.lifecycle_state is distinct from old.lifecycle_state then
    mapped_state := new.lifecycle_state;
    new.status := case mapped_state
      when 'successfully_completed' then 'completed'
      else mapped_state
    end;
  elsif new.status is distinct from old.status then
    mapped_state := case lower(btrim(new.status))
      when 'settlement_pending' then 'settlement_pending'
      when 'completed' then 'successfully_completed'
      when 'successfully_completed' then 'successfully_completed'
      when 'cancelled' then 'cancelled'
      when 'canceled' then 'cancelled'
      when 'rescheduled' then 'rescheduled'
      else 'scheduled'
    end;
    new.lifecycle_state := mapped_state;
  else
    mapped_state := old.lifecycle_state;
  end if;

  if old.lifecycle_state = 'successfully_completed'
    and new.lifecycle_state = 'rescheduled' then
    if new.successor_id is null
      or not exists (
        select 1 from app.lessons successor
        where successor.id = new.successor_id
          and successor.predecessor_id = old.id
          and successor.lifecycle_state = 'scheduled'
          and successor.deleted_at is null
      )
      or not exists (
        select 1 from app.lesson_settlement_corrections correction
        where correction.lesson_id = old.id
      ) then
      raise exception using
        errcode = '23514',
        message = 'completed lesson reschedule requires correction and successor';
    end if;
  elsif old.lifecycle_state in (
    'successfully_completed',
    'cancelled',
    'rescheduled'
  ) and new.lifecycle_state is distinct from old.lifecycle_state then
    raise exception using
      errcode = '23514',
      message = 'terminal lesson lifecycle cannot transition';
  end if;

  if old.lifecycle_state = 'scheduled'
    and new.lifecycle_state not in (
      'scheduled',
      'settlement_pending',
      'successfully_completed',
      'cancelled',
      'rescheduled'
    ) then
    raise exception using
      errcode = '23514',
      message = 'illegal lesson lifecycle transition';
  end if;

  if old.lifecycle_state = 'settlement_pending'
    and new.lifecycle_state not in (
      'settlement_pending',
      'successfully_completed',
      'cancelled',
      'rescheduled'
    ) then
    raise exception using
      errcode = '23514',
      message = 'illegal lesson lifecycle transition';
  end if;

  new.version := greatest(
    coalesce(new.version, old.version),
    old.version + 1
  );
  return new;
end;
$$;
