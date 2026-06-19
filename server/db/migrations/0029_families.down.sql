-- server/db/migrations/0029_families.down.sql
drop table if exists app.contacts;
alter table app.families drop constraint if exists families_payer_member_fk;
drop table if exists app.family_members;
drop table if exists app.families;
