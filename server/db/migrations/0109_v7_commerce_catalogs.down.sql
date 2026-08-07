do $$
declare
  defaults jsonb := '{
    "lessonSettlementTypes": [
      {"stableKey":"lesson","label":"Занятие","colorToken":"success","hourShareBasisPoints":10000,"allowedContexts":["settle"],"active":true,"order":0},
      {"stableKey":"partially_paid_lesson","label":"Частично оплачиваемое занятие","colorToken":"info","hourShareBasisPoints":5000,"allowedContexts":["settle"],"active":true,"order":1},
      {"stableKey":"free_lesson","label":"Бесплатное занятие","colorToken":"warning","hourShareBasisPoints":0,"allowedContexts":["cancel","reschedule","settle"],"active":true,"order":2},
      {"stableKey":"paid_miss","label":"Оплачиваемый пропуск","colorToken":"blue","hourShareBasisPoints":10000,"allowedContexts":["cancel","reschedule","settle"],"active":true,"order":3},
      {"stableKey":"partially_paid_miss","label":"Частично оплачиваемый пропуск","colorToken":"cyan","hourShareBasisPoints":5000,"allowedContexts":["cancel","reschedule","settle"],"active":true,"order":4},
      {"stableKey":"unpaid_miss","label":"Неоплачиваемый пропуск","colorToken":"neutral","hourShareBasisPoints":0,"allowedContexts":["cancel","reschedule","settle"],"active":true,"order":5},
      {"stableKey":"penalty_lesson","label":"Занятие со штрафом","colorToken":"violet","hourShareBasisPoints":10000,"fixedPenaltyMinor":"0","allowedContexts":["cancel","reschedule","settle"],"active":true,"order":6}
    ],
    "teacherCompensationRules": [
      {"stableKey":"none","label":"Не оплачивать","mode":"none","value":"0","active":true,"order":0},
      {"stableKey":"standard","label":"Полная стандартная ставка","mode":"standard","value":"0","active":true,"order":1},
      {"stableKey":"percent","label":"Процент ставки","mode":"percent","value":"10000","active":true,"order":2},
      {"stableKey":"fixed","label":"Фиксированная сумма","mode":"fixed","value":"0","active":true,"order":3},
      {"stableKey":"hourly","label":"Почасовая сумма","mode":"hourly","value":"0","active":true,"order":4}
    ]
  }'::jsonb;
begin
  if exists (
    select 1
    from app.crm_configuration_revisions
    where effective_snapshot->'lessonSettlementTypes'
            is distinct from defaults->'lessonSettlementTypes'
       or effective_snapshot->'teacherCompensationRules'
            is distinct from defaults->'teacherCompensationRules'
  ) or exists (
    select 1
    from app.crm_configuration_drafts
    where snapshot->'lessonSettlementTypes'
            is distinct from defaults->'lessonSettlementTypes'
       or snapshot->'teacherCompensationRules'
            is distinct from defaults->'teacherCompensationRules'
  ) then
    raise exception
      '0109 down blocked: configured commerce catalogs would be destroyed';
  end if;
end $$;

drop trigger if exists crm_configuration_revision_immutable
  on app.crm_configuration_revisions;

update app.crm_configuration_revisions
set effective_snapshot = effective_snapshot
      - 'lessonSettlementTypes' - 'teacherCompensationRules',
    patch = patch - 'lessonSettlementTypes' - 'teacherCompensationRules';

update app.crm_configuration_drafts
set snapshot = snapshot
      - 'lessonSettlementTypes' - 'teacherCompensationRules';

create trigger crm_configuration_revision_immutable
before update or delete on app.crm_configuration_revisions
for each row execute function app.protect_crm_configuration_revision();
