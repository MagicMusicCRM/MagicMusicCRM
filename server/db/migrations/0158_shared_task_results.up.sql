-- Task completion result is part of the immutable close fact. Historical
-- closes stay nullable because their result was never captured.

alter table app.task_closes
  add column if not exists result_code text,
  add column if not exists result_label text,
  add column if not exists comment text,
  add column if not exists planned_start_at timestamptz,
  add column if not exists planned_all_day boolean,
  add column if not exists was_overdue boolean;

alter table app.task_closes
  drop constraint if exists task_closes_result_check;
alter table app.task_closes
  add constraint task_closes_result_check
  check (
    (
      result_code is null
      and result_label is null
      and comment is null
    )
    or (
      nullif(btrim(result_code), '') is not null
      and result_code ~ '^[a-z0-9][a-z0-9._-]*$'
      and nullif(btrim(result_label), '') is not null
      and (result_code <> 'other' or nullif(btrim(comment), '') is not null)
    )
  );

create index if not exists task_closes_results_idx
  on app.task_closes (closed_at desc, result_code, closed_by);
