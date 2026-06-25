create table if not exists app.chat_work_events (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references app.chats(id) on delete cascade,
  actor_user_id uuid references app.users(id) on delete set null,
  target_user_id uuid references app.users(id) on delete set null,
  previous_assigned_user_id uuid references app.users(id) on delete set null,
  action text not null check (action in ('claimed', 'unassigned')),
  created_at timestamptz not null default now()
);

create index if not exists chat_work_events_chat_created_idx
  on app.chat_work_events (chat_id, created_at desc);

create index if not exists chat_work_events_actor_created_idx
  on app.chat_work_events (actor_user_id, created_at desc)
  where actor_user_id is not null;
