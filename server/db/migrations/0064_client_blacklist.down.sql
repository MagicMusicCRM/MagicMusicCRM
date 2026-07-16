-- Возвращаем галочку в custom_data, чтобы откат не потерял, кого отметили.
-- Причина и автор бана при откате теряются — в custom_data их некуда положить.
update app.students
set custom_data = jsonb_set(custom_data, '{blacklisted}', 'true'::jsonb)
where blacklisted = true and deleted_at is null;

drop index if exists app.students_blacklisted_idx;
drop index if exists app.leads_blacklisted_idx;

alter table app.students
  drop column if exists blacklisted,
  drop column if exists blacklisted_at,
  drop column if exists blacklisted_by,
  drop column if exists blacklist_reason;

alter table app.leads
  drop column if exists blacklisted,
  drop column if exists blacklisted_at,
  drop column if exists blacklisted_by,
  drop column if exists blacklist_reason;
