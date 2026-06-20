-- Fixture for Docker validation of 0032 (run AFTER 0031, BEFORE 0032).
-- NOT auto-discovered: it lives under __fixtures__/, not migrations/ root, so the
-- runner's *.up.sql glob ignores it. Referenced only by the validation step.
insert into app.lead_statuses (name, sort_order, color, is_terminal, requires_reason) values
  ('Новый', 10, '#C5A059', false, false),
  ('Контакт', 20, null, false, false),       -- legacy, will be empty -> deleted
  ('Переговоры', 30, null, false, false),     -- legacy, empty -> deleted
  ('Договор', 40, null, false, false),        -- legacy, NON-empty below -> NOT deleted
  ('Успешный', 50, '#43A047', false, false),
  ('Отказ', 60, '#888888', false, false);

-- One lead with NULL status (-> migrates to «Новый»).
insert into app.leads (first_name, last_name, phone) values ('Без', 'Статуса', '+70000000001');
-- One lead pinned to «Договор» so that legacy column is NON-empty (must survive).
insert into app.leads (status_id, first_name, last_name)
select id, 'Имеет', 'Договор' from app.lead_statuses where name = 'Договор';
