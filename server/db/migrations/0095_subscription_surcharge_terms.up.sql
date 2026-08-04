alter table app.subscriptions
  add column if not exists surcharge_minor bigint,
  add column if not exists surcharge_reason text;

alter table app.subscriptions
  drop constraint if exists subscriptions_commercial_snapshot_shape;

alter table app.subscriptions
  add constraint subscriptions_commercial_snapshot_shape
  check (
    (
      commercial_snapshot is null
      and snapshot_version is null
      and package_version is null
      and base_price_minor is null
      and currency_code is null
      and discount_type is null
      and discount_percent_basis_points is null
      and discount_fixed_minor is null
      and discount_reason is null
      and surcharge_minor is null
      and surcharge_reason is null
      and final_price_minor is null
    )
    or
    (
      jsonb_typeof(commercial_snapshot) = 'object'
      and snapshot_version >= 1
      and package_id is not null
      and package_version >= 1
      and base_price_minor >= 0
      and currency_code ~ '^[A-Z]{3}$'
      and final_price_minor >= 0
      and (
        (surcharge_minor is null and surcharge_reason is null)
        or (
          surcharge_minor > 0
          and nullif(btrim(surcharge_reason), '') is not null
        )
      )
      and final_price_minor = (
        case
          when discount_type is null
            and discount_percent_basis_points is null
            and discount_fixed_minor is null
            and discount_reason is null
            then base_price_minor
          when discount_type = 'percent'
            and discount_percent_basis_points between 1 and 10000
            and discount_fixed_minor is null
            and nullif(btrim(discount_reason), '') is not null
            then greatest(
              0,
              base_price_minor - round(
                base_price_minor::numeric
                  * discount_percent_basis_points / 10000
              )::bigint
            )
          when discount_type = 'fixed'
            and discount_percent_basis_points is null
            and discount_fixed_minor between 1 and base_price_minor
            and nullif(btrim(discount_reason), '') is not null
            then base_price_minor - discount_fixed_minor
          else null
        end
        + coalesce(surcharge_minor, 0)
      )
    )
  );

create or replace function app.protect_issued_subscription_snapshot()
returns trigger
language plpgsql
as $$
begin
  if old.commercial_snapshot is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op = 'DELETE'
    or new.student_id is distinct from old.student_id
    or new.package_id is distinct from old.package_id
    or new.lessons_total is distinct from old.lessons_total
    or new.starts_at is distinct from old.starts_at
    or new.expires_at is distinct from old.expires_at
    or new.commercial_snapshot is distinct from old.commercial_snapshot
    or new.snapshot_version is distinct from old.snapshot_version
    or new.package_version is distinct from old.package_version
    or new.base_price_minor is distinct from old.base_price_minor
    or new.currency_code is distinct from old.currency_code
    or new.discount_type is distinct from old.discount_type
    or new.discount_percent_basis_points is distinct from old.discount_percent_basis_points
    or new.discount_fixed_minor is distinct from old.discount_fixed_minor
    or new.discount_reason is distinct from old.discount_reason
    or new.surcharge_minor is distinct from old.surcharge_minor
    or new.surcharge_reason is distinct from old.surcharge_reason
    or new.final_price_minor is distinct from old.final_price_minor then
    raise exception using
      errcode = '23514',
      message = 'issued subscription commercial snapshot is immutable';
  end if;
  return new;
end;
$$;
