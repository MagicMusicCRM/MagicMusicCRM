alter table app.expenses add column version bigint not null default 1,
  add column occurred_at timestamptz;
comment on column app.expenses.occurred_at is 'Business date. NULL on legacy rows means unknown; reporting falls back to recorded created_at.';
create table app.expense_revisions (
  expense_id uuid not null references app.expenses(id) on delete restrict,
  version bigint not null check(version > 0),
  amount numeric(12,2) not null,
  category text not null,
  description text,
  branch_id uuid references app.branches(id) on delete restrict,
  occurred_at timestamptz,
  expense_created_at timestamptz not null,
  deleted_at timestamptz,
  recorded_at timestamptz not null default now(),
  baseline boolean not null default false,
  primary key(expense_id,version)
);
insert into app.expense_revisions(expense_id,version,amount,category,description,branch_id,occurred_at,expense_created_at,deleted_at,baseline)
  select id,version,amount,category,description,branch_id,occurred_at,created_at,deleted_at,true from app.expenses;
insert into app.aggregate_versions(aggregate_type,aggregate_id,version)
  select 'commerce:expense',id,version from app.expenses;
create trigger expense_revisions_immutable before update or delete on app.expense_revisions
  for each row execute function app.reject_immutable_commerce_fact();
create index expenses_occurred_idx on app.expenses(coalesce(occurred_at,created_at) desc,id desc) where deleted_at is null;
do $$ begin
  if exists(select 1 from pg_roles where rolname='magiccrm_app') then
    grant select,insert on app.expense_revisions to magiccrm_app;
  end if;
end $$;
