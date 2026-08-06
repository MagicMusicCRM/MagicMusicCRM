alter table app.account_adjustments
  add column if not exists amount_minor bigint,
  add column if not exists currency_code text,
  add column if not exists source_payment_id uuid
    references app.payments(id) on delete restrict,
  add column if not exists idempotency_ref text,
  add column if not exists request_fingerprint text;

update app.account_adjustments
set
  amount_minor = round(amount * 100)::bigint,
  currency_code = coalesce(legacy_payment_currency, 'RUB')
where amount_minor is null or currency_code is null;

create or replace function app.fill_account_adjustment_minor_units()
returns trigger
language plpgsql
as $$
begin
  if new.amount_minor is null then
    new.amount_minor := round(new.amount * 100)::bigint;
  elsif new.amount is null then
    new.amount := new.amount_minor::numeric / 100;
  elsif new.amount_minor <> round(new.amount * 100)::bigint then
    raise exception using
      errcode = '23514',
      message = 'account adjustment amount/minor-unit mismatch';
  end if;
  new.currency_code := coalesce(new.currency_code, 'RUB');
  return new;
end;
$$;

drop trigger if exists account_adjustments_fill_minor_units
  on app.account_adjustments;
create trigger account_adjustments_fill_minor_units
before insert or update of amount, amount_minor, currency_code
on app.account_adjustments
for each row execute function app.fill_account_adjustment_minor_units();

alter table app.account_adjustments
  alter column amount_minor set not null,
  alter column currency_code set not null,
  add constraint account_adjustments_amount_minor_nonzero
    check (amount_minor <> 0),
  add constraint account_adjustments_currency_code_check
    check (currency_code ~ '^[A-Z]{3}$'),
  add constraint account_adjustments_source_shape_check
    check (
      (
        source_payment_id is null
        and idempotency_ref is null
        and request_fingerprint is null
      )
      or (
        source_payment_id is not null
        and kind in ('refund', 'adjustment')
        and nullif(btrim(idempotency_ref), '') is not null
        and nullif(btrim(request_fingerprint), '') is not null
      )
    );

create unique index if not exists account_adjustments_v4_idempotency_idx
  on app.account_adjustments(student_id, idempotency_ref)
  where idempotency_ref is not null;
create index if not exists account_adjustments_source_payment_idx
  on app.account_adjustments(source_payment_id, occurred_at, id)
  where source_payment_id is not null;

drop trigger if exists account_adjustments_source_immutable
  on app.account_adjustments;
create trigger account_adjustments_source_immutable
before update or delete on app.account_adjustments
for each row
when (old.source_payment_id is not null)
execute function app.reject_immutable_commerce_fact();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.account_adjustments to magiccrm_app;
    revoke update, delete on app.account_adjustments from magiccrm_app;
  end if;
end
$$;
