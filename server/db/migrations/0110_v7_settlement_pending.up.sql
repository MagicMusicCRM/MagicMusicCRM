-- v7 T3.1.4: elapsed lessons wait for an explicit, actor-confirmed settlement.

alter table app.lessons
  drop constraint if exists lessons_lifecycle_state_check;

alter table app.lessons
  add constraint lessons_lifecycle_state_check
  check (
    lifecycle_state in (
      'scheduled',
      'settlement_pending',
      'successfully_completed',
      'cancelled',
      'rescheduled'
    )
  );

alter table app.lesson_transitions
  drop constraint if exists lesson_transitions_state_check;

alter table app.lesson_transitions
  add constraint lesson_transitions_state_check
  check (
    from_state in ('scheduled', 'settlement_pending')
    and to_state in (
      'successfully_completed',
      'cancelled',
      'rescheduled'
    )
  );

alter table app.lesson_completion_work
  drop constraint if exists lesson_completion_work_terminal_state_check;

alter table app.lesson_completion_work
  add constraint lesson_completion_work_terminal_state_check
  check (
    terminal_state is null
    or terminal_state in (
      'settlement_pending',
      'successfully_completed',
      'cancelled',
      'rescheduled'
    )
  );

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

  if old.lifecycle_state in (
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

