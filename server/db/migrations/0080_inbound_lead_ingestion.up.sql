-- v4 T3.2.1: retain the integration identity on an inbound Lead as a
-- database-level second line of defence behind platform idempotency.

alter table app.leads
  add column if not exists inbound_id text;

create unique index if not exists leads_inbound_id_unique_idx
  on app.leads (inbound_id)
  where inbound_id is not null;
