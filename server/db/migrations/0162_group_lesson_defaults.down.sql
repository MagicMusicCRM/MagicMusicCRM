alter table app.groups
  drop constraint group_lesson_defaults_pair,
  drop column teacher_compensation_rule_key,
  drop column settlement_type_key;
