-- Чёрный список клиента — настоящий бан.
--
-- ✔ Решение владельца 17.07: «при назначении этого статуса карточка клиента
-- помечается красным цветом предупреждения, и этот клиент не может писать
-- далее в чатах школы и админам — по сути бан».
--
-- Раньше это было generic-булево кастом-поле `custom_data.blacklisted`: его
-- можно было включить, и не происходило ровно ничего. Ни автора, ни причины,
-- ни последствий — галочка, о которой знал только тот, кто её поставил.
--
-- Поля заводятся и на учениках, и на лидах, потому что клиентский аккаунт
-- цепляется к любой из половин (app.user_crm_links.entity_type in
-- ('student','lead')). Бан только на ученике оставил бы лид-половине открытый
-- чат — то есть не банил бы.

alter table app.students
  add column if not exists blacklisted boolean not null default false,
  add column if not exists blacklisted_at timestamptz,
  add column if not exists blacklisted_by uuid references app.users(id) on delete set null,
  add column if not exists blacklist_reason text;

alter table app.leads
  add column if not exists blacklisted boolean not null default false,
  add column if not exists blacklisted_at timestamptz,
  add column if not exists blacklisted_by uuid references app.users(id) on delete set null,
  add column if not exists blacklist_reason text;

-- Переносим то, что уже наотмечали галочкой. Автора и время взять неоткуда —
-- их никто не писал; blacklisted_at остаётся null и означает «до миграции».
update app.students
set blacklisted = true
where deleted_at is null
  and custom_data->>'blacklisted' in ('true', 't', '1');

-- Ключ убираем: два источника правды разъедутся в первый же день, а поле,
-- в которое пишут и которое никто не читает, — это ровно тот дефект, который
-- здесь и чинится.
update app.students
set custom_data = custom_data - 'blacklisted'
where custom_data ? 'blacklisted';

-- Бан проверяется на каждой отправке сообщения, а забаненных единицы —
-- частичный индекс, чтобы не тащить всю таблицу.
create index if not exists students_blacklisted_idx
  on app.students (id)
  where blacklisted = true and deleted_at is null;

create index if not exists leads_blacklisted_idx
  on app.leads (id)
  where blacklisted = true and deleted_at is null;
