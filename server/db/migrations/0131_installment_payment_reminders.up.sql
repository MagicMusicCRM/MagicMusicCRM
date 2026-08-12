-- UAT-025: consume the effective school/branch payment_reminder_days setting.
-- One durable row represents one advance reminder for one immutable installment.
-- Delivery state is mutable and leased, while the reminder identity/snapshot is
-- protected so retries cannot silently change the audience or due date.

create table if not exists app.installment_payment_reminders (
  id uuid primary key default gen_random_uuid(),
  installment_id uuid not null unique
    references app.subscription_installments(id) on delete restrict,
  recipient_user_ids uuid[] not null default '{}'::uuid[],
  due_at timestamptz not null,
  reminder_days integer not null,
  status text not null default 'pending',
  attempts integer not null default 0,
  next_attempt_at timestamptz,
  claimed_by text,
  claimed_at timestamptz,
  delivered_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint installment_payment_reminders_days_check
    check (reminder_days between 0 and 60),
  constraint installment_payment_reminders_attempts_check
    check (attempts >= 0),
  constraint installment_payment_reminders_recipients_check
    check (array_position(recipient_user_ids, null) is null),
  constraint installment_payment_reminders_status_check
    check (status in ('pending', 'claimed', 'delivered', 'cancelled', 'poison')),
  constraint installment_payment_reminders_claim_check
    check (
      (status = 'claimed' and claimed_by is not null and claimed_at is not null)
      or status <> 'claimed'
    )
);

create index if not exists installment_payment_reminders_due_idx
  on app.installment_payment_reminders (
    status,
    coalesce(next_attempt_at, created_at),
    id
  )
  where status in ('pending', 'claimed');

create or replace function app.protect_installment_payment_reminder_identity()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE'
    or new.installment_id is distinct from old.installment_id
    or new.recipient_user_ids is distinct from old.recipient_user_ids
    or new.due_at is distinct from old.due_at
    or new.reminder_days is distinct from old.reminder_days
    or new.created_at is distinct from old.created_at then
    raise exception using
      errcode = '23514',
      message = 'installment payment reminder identity is immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists installment_payment_reminders_protect
  on app.installment_payment_reminders;
create trigger installment_payment_reminders_protect
before update or delete on app.installment_payment_reminders
for each row execute function app.protect_installment_payment_reminder_identity();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update on app.installment_payment_reminders
      to magiccrm_app;
  end if;
end $$;
