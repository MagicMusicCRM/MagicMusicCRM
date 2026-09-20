-- Append the new catalog; do not reinterpret stored plans or financial facts.
select pg_advisory_xact_lock(hashtext('crm-configuration:school'));
with latest as (
  select version, effective_snapshot from app.crm_configuration_revisions
  where branch_id is null order by version desc limit 1
), revised as (
  select version,
    jsonb_set(jsonb_set(effective_snapshot, '{lessonSettlementTypes}',
      (select coalesce(jsonb_agg(item), '[]'::jsonb)
       from jsonb_array_elements(effective_snapshot->'lessonSettlementTypes') item
       where item->>'stableKey' <> 'trial_lesson') ||
      '[{"stableKey":"trial_lesson","label":"Пробный урок","colorToken":"violet","hourShareBasisPoints":0,"clientDurationMode":"zero","teacherDurationMode":"full","defaultTeacherCompensationRuleKey":"trial_lesson","fixedPenaltyMinor":"0","allowedContexts":["settle"],"active":true,"order":7}]'::jsonb),
      '{teacherCompensationRules}',
      (select coalesce(jsonb_agg(item), '[]'::jsonb)
       from jsonb_array_elements(effective_snapshot->'teacherCompensationRules') item
       where item->>'stableKey' <> 'trial_lesson') ||
      '[{"stableKey":"trial_lesson","label":"Пробный урок — без оплаты","mode":"none","value":"0","active":true,"order":5}]'::jsonb
    ) as snapshot
  from latest
)
insert into app.crm_configuration_revisions
  (branch_id, version, patch, effective_snapshot, impact, reason)
select null, version + 1, snapshot, snapshot,
  '{"migration":"0156_trial_lesson_catalog","systemOwnedCatalog":true}'::jsonb,
  'Пробный урок: бесплатно клиенту, преподавателю без оплаты до ручного изменения'
from revised;
