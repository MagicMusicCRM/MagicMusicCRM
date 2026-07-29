-- v4 T8.2.1: durable coordination state for automatic Lesson completion.

create table if not exists app.lesson_completion_work (
  lesson_id uuid primary key references app.lessons(id) on delete cascade,
  state text not null default 'claimed',
  lesson_version bigint not null,
  scheduled_end_at timestamptz not null,
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  claimed_at timestamptz,
  claimed_by text,
  completed_at timestamptz,
  transition_id uuid references app.lesson_transitions(id) on delete restrict,
  client_financial_fact_id uuid
    references app.lesson_client_charge_facts(id) on delete restrict,
  teacher_financial_fact_id uuid
    references app.lesson_teacher_compensation_facts(id) on delete restrict,
  terminal_state text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint lesson_completion_work_state_check
    check (state in ('claimed', 'retry', 'completed', 'poison')),
  constraint lesson_completion_work_version_positive
    check (lesson_version > 0),
  constraint lesson_completion_work_attempts_nonnegative
    check (attempts >= 0),
  constraint lesson_completion_work_claim_shape
    check (
      (state = 'claimed' and claimed_at is not null and claimed_by is not null)
      or (state <> 'claimed' and claimed_at is null and claimed_by is null)
    ),
  constraint lesson_completion_work_completion_shape
    check (
      (state = 'completed' and completed_at is not null)
      or (state <> 'completed' and completed_at is null)
    ),
  constraint lesson_completion_work_terminal_state_check
    check (
      terminal_state is null
      or terminal_state in (
        'successfully_completed',
        'cancelled',
        'rescheduled'
      )
    )
);

create index if not exists lesson_completion_work_due_idx
  on app.lesson_completion_work (state, available_at, lesson_id)
  where state in ('retry', 'claimed');

create index if not exists lesson_completion_work_claim_lease_idx
  on app.lesson_completion_work (claimed_at, lesson_id)
  where state = 'claimed';

create index if not exists lesson_completion_work_poison_idx
  on app.lesson_completion_work (updated_at, lesson_id)
  where state = 'poison';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update on app.lesson_completion_work to magiccrm_app;
  end if;
end $$;
