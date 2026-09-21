// Canonical paid-unit projection shared by staff finance reads and automatic settlement.
// The enclosing query must bind app.subscriptions as issued.
export const subscriptionFundingSql = `
            with recursive lifecycle_chain(id) as (
              select issued.id
              union
              select event.before_issued_subscription_id
              from app.subscription_lifecycle_events event
              join lifecycle_chain current
                on current.id = event.after_issued_subscription_id
              where event.event_type = 'replace'
            ), raw_totals as (
              select
                coalesce((
                  select sum(payment.amount_minor)
                   from app.commerce_ordinary_payments payment
                  where payment.issued_subscription_id in (
                    select id from lifecycle_chain
                  )
                    and payment.deleted_at is null
                ), 0)::numeric
                + coalesce((
                  select sum(adjustment.amount_minor)
                   from app.commerce_ordinary_account_adjustments adjustment
                   join app.commerce_ordinary_payments source_payment
                    on source_payment.id = adjustment.source_payment_id
                  where source_payment.issued_subscription_id in (
                    select id from lifecycle_chain
                  )
                    and adjustment.deleted_at is null
                    and adjustment.status = 'paid'
                ), 0)::numeric
                as actual_paid_minor,
                coalesce((
                  select sum(
                    case
                      when obligation.direction = 'debit'
                        then obligation.amount_minor
                      else -obligation.amount_minor
                    end
                  )
                  from app.subscription_obligation_facts obligation
                  where obligation.issued_subscription_id in (
                    select id from lifecycle_chain
                  )
                ), 0)::numeric as obligation_minor,
                coalesce((
                  select sum(record.amount_minor)
                   from app.commerce_ordinary_payment_records record
                  where record.issued_subscription_id in (
                    select id from lifecycle_chain
                  )
                    and record.status = 'posted_pending'
                ), 0)::numeric as pending_minor,
                coalesce((
                  select sum(record.amount_minor)
                   from app.commerce_ordinary_payment_records record
                  where record.issued_subscription_id in (
                    select id from lifecycle_chain
                  )
                    and record.status = 'unpaid'
                ), 0)::numeric as debt_minor
            ), funding_credit as (
              select greatest(raw_totals.actual_paid_minor - coalesce(
                (issued.commercial_snapshot #>> '{commercialRules,priorConsumedValueMinor}')::numeric, 0
              ), 0) as available_paid_minor
              from raw_totals
            ), totals as (
              select
                funding_credit.available_paid_minor as actual_paid_minor,
                raw_totals.obligation_minor - raw_totals.actual_paid_minor
                  + funding_credit.available_paid_minor as obligation_minor,
                raw_totals.pending_minor, raw_totals.debt_minor
              from raw_totals cross join funding_credit
            )
            select
              totals.actual_paid_minor,
              totals.obligation_minor,
              totals.pending_minor,
              totals.debt_minor,
              case
                when totals.obligation_minor <= 0 then
                  coalesce((issued.commercial_snapshot ->> 'unitCount')::numeric, issued.lessons_total)
                else least(
                  coalesce((issued.commercial_snapshot ->> 'unitCount')::numeric, issued.lessons_total),
                  greatest(totals.actual_paid_minor, 0)
                    * coalesce((issued.commercial_snapshot ->> 'unitCount')::numeric, issued.lessons_total)
                    / totals.obligation_minor
                )
              end as paid_units,
              (
                select min(pending.due_at)
                from (
                  select
                    coalesce(due_fact.due_at, installment.due_at) as due_at,
                    greatest(
                      totals.obligation_minor - coalesce(sum(
                        case
                          when installment.status = 'void' then 0
                          else installment.amount_minor
                        end
                      ) over (), 0),
                      0
                    ) + sum(
                      case
                        when installment.status = 'void' then 0
                        else installment.amount_minor
                      end
                    ) over (order by installment.installment_number)
                      as cumulative_minor
                  from app.subscription_installments installment
                  left join app.subscription_installment_due_facts due_fact
                    on due_fact.installment_id = installment.id
                  where installment.issued_subscription_id = issued.id
                ) pending
                where pending.cumulative_minor > totals.actual_paid_minor
              ) as next_payment_at
            from totals
`;
