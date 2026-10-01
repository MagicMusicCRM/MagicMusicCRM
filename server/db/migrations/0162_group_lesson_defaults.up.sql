alter table app.groups
  add column settlement_type_key text,
  add column teacher_compensation_rule_key text,
  add constraint group_lesson_defaults_pair check (
    (settlement_type_key is null and teacher_compensation_rule_key is null)
    or (settlement_type_key is not null and teacher_compensation_rule_key is not null
      and length(trim(settlement_type_key)) between 1 and 120
      and length(trim(teacher_compensation_rule_key)) between 1 and 120)
  );
