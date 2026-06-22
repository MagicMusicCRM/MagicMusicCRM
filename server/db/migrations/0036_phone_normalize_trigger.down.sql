-- server/db/migrations/0036_phone_normalize_trigger.down.sql
drop trigger if exists set_phone_normalized on app.users;
drop trigger if exists set_phone_normalized on app.profiles;
drop trigger if exists set_phone_normalized on app.leads;
drop function if exists app.trg_set_phone_normalized();
drop function if exists app.fn_normalize_phone(text);
