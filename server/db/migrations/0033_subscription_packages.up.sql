-- P5b (KVA-199): subscription packages catalog + issuance link.

create table if not exists app.subscription_packages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  discipline_id uuid references app.disciplines(id),
  branch_id uuid references app.branches(id),
  lessons_total integer not null check (lessons_total > 0),
  price numeric(12, 2) not null check (price >= 0),
  validity_days integer,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists subscription_packages_active_idx
  on app.subscription_packages (sort_order, name)
  where deleted_at is null;

-- Link a sold subscription back to the catalog row + the payment it created.
alter table app.subscriptions
  add column if not exists package_id uuid references app.subscription_packages(id),
  add column if not exists payment_id uuid references app.payments(id);

-- P5b-4: the subscription a present-mark was counted against, so the
-- lessons_used decrement stays idempotent per lesson_participation row.
alter table app.lesson_participation
  add column if not exists subscription_id uuid references app.subscriptions(id);
