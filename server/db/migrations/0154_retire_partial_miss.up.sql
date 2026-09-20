-- Retire the school option by appending a revision; frozen history stays intact.
with latest_school as (
  select version, effective_snapshot
  from app.crm_configuration_revisions
  where branch_id is null
  order by version desc limit 1
), retired_school as (
  select version, jsonb_set(effective_snapshot, '{lessonSettlementTypes}', (
    select jsonb_agg(case
      when item->>'stableKey' = 'partially_paid_miss'
        then item || '{"active":false}'::jsonb
      else item end order by ordinality)
    from jsonb_array_elements(effective_snapshot->'lessonSettlementTypes')
      with ordinality as types(item, ordinality)
  )) as effective_snapshot
  from latest_school
  where exists (
    select 1 from jsonb_array_elements(effective_snapshot->'lessonSettlementTypes') item
    where item->>'stableKey' = 'partially_paid_miss' and item->>'active' = 'true'
  )
)
insert into app.crm_configuration_revisions (
  branch_id, version, patch, effective_snapshot, impact, reason
)
select null, version + 1, effective_snapshot, effective_snapshot,
  '{"migration":"0154_retire_partial_miss","systemOwnedCatalog":true}'::jsonb,
  'Отключён неиспользуемый тип: Частично оплачиваемый пропуск'
from retired_school;

-- Drafts must not resurrect a retired system-owned type on publication.
update app.crm_configuration_drafts draft
set snapshot = jsonb_set(draft.snapshot, '{lessonSettlementTypes}', (
  select jsonb_agg(case
    when item->>'stableKey' = 'partially_paid_miss'
      then item || '{"active":false}'::jsonb
    else item end order by ordinality)
  from jsonb_array_elements(draft.snapshot->'lessonSettlementTypes')
    with ordinality as types(item, ordinality)
))
where exists (
  select 1 from jsonb_array_elements(draft.snapshot->'lessonSettlementTypes') item
  where item->>'stableKey' = 'partially_paid_miss' and item->>'active' = 'true'
);
