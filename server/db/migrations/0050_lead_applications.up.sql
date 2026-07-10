-- KVA-233: заявки лида из HolliHop GetStudyRequests — секция «Заявки» в
-- карточке лида (повторные обращения с датой, каналом и UTM-метками).
create table if not exists app.lead_applications (
  id uuid primary key,
  lead_id uuid not null references app.leads(id) on delete cascade,
  applied_at timestamptz not null,
  channel text,
  office text,
  discipline text,
  status text,
  utm jsonb,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists lead_applications_lead_idx
  on app.lead_applications (lead_id, applied_at desc)
  where deleted_at is null;
