with latest_school as (
  select version, effective_snapshot
  from app.crm_configuration_revisions
  where branch_id is null
  order by version desc
  limit 1
), normalized_school as (
  select
    version,
    jsonb_set(
      effective_snapshot,
      '{lessonSettlementTypes}',
      coalesce((
        select jsonb_agg(
          settlement_type.item || jsonb_build_object(
            'clientDurationMode', case
              when (settlement_type.item->>'hourShareBasisPoints')::integer = 0 then 'zero'
              when (settlement_type.item->>'hourShareBasisPoints')::integer = 10000 then 'full'
              else 'manual'
            end,
            'teacherDurationMode', case
              when (settlement_type.item->>'hourShareBasisPoints')::integer = 0 then 'zero'
              when (settlement_type.item->>'hourShareBasisPoints')::integer = 10000 then 'full'
              else 'manual'
            end,
            'defaultTeacherCompensationRuleKey', case
              when (settlement_type.item->>'hourShareBasisPoints')::integer = 0 then 'none'
              when (settlement_type.item->>'hourShareBasisPoints')::integer = 10000 then 'standard'
              else 'percent'
            end,
            'active', case
              when settlement_type.item->>'stableKey' = 'penalty_lesson' then false
              else (settlement_type.item->>'active')::boolean
            end
          ) order by settlement_type.ordinality
        )
        from jsonb_array_elements(
          latest_school.effective_snapshot->'lessonSettlementTypes'
        ) with ordinality as settlement_type(item, ordinality)
      ), '[]'::jsonb),
      true
    ) as effective_snapshot
  from latest_school
)
insert into app.crm_configuration_revisions (
  branch_id, version, patch, effective_snapshot, impact, reason
)
select
  null,
  normalized_school.version + 1,
  normalized_school.effective_snapshot,
  normalized_school.effective_snapshot,
  jsonb_build_object(
    'migration', '0149_lesson_settlement_policy_revision',
    'systemOwnedCatalog', true
  ),
  'Системная нормализация правил расчёта занятий'
from normalized_school
where jsonb_typeof(
  normalized_school.effective_snapshot->'lessonSettlementTypes'
) = 'array'
and not exists (
  select 1
  from app.crm_configuration_revisions revision
  where revision.impact->>'migration' =
    '0149_lesson_settlement_policy_revision'
);

with active_settlement_catalog as (
  select effective_snapshot->'lessonSettlementTypes' as settlement_types
  from app.crm_configuration_revisions
  where branch_id is null
  order by version desc
  limit 1
)
update app.crm_configuration_drafts draft
set snapshot = jsonb_set(
  draft.snapshot,
  '{lessonSettlementTypes}',
  active_settlement_catalog.settlement_types,
  true
)
from active_settlement_catalog;
