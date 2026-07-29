drop index if exists app.leads_inbound_id_unique_idx;

alter table app.leads
  drop column if exists inbound_id;
