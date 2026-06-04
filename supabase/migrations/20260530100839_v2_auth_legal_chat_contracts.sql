-- MagicMusicCRM v2 auth/legal/account deletion and messaging contracts.
-- Adds release-blocking backend primitives for onboarding, legal consent,
-- account deletion requests, personal administration chat and announcements.

begin;

-- ── Onboarding state ────────────────────────────────────────────────────────

alter table public.profiles
  add column if not exists profile_completed_at timestamptz;

update public.profiles
set profile_completed_at = coalesce(created_at, now())
where profile_completed_at is null
  and nullif(trim(coalesce(first_name, '')), '') is not null
  and nullif(trim(coalesce(last_name, '')), '') is not null
  and nullif(trim(coalesce(phone, '')), '') is not null;

create or replace function public.complete_onboarding(
  p_first_name text,
  p_last_name text,
  p_phone text
)
returns void
language plpgsql
security invoker
set search_path = public
as $function$
begin
  if auth.uid() is null then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_first_name, '')), '') is null
     or nullif(trim(coalesce(p_last_name, '')), '') is null
     or nullif(trim(coalesce(p_phone, '')), '') is null then
    raise exception 'first name, last name and phone are required' using errcode = '22023';
  end if;

  update public.profiles
  set first_name = trim(p_first_name),
      last_name = trim(p_last_name),
      phone = trim(p_phone),
      profile_completed_at = coalesce(profile_completed_at, now())
  where id = auth.uid();

  if not found then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;
end;
$function$;

revoke execute on function public.complete_onboarding(text, text, text) from public, anon;
grant execute on function public.complete_onboarding(text, text, text) to authenticated;

-- ── Legal documents and immutable consent records ───────────────────────────

create table if not exists public.legal_documents (
  id uuid primary key default gen_random_uuid(),
  document_type text not null
    check (document_type in ('privacy_policy', 'terms_of_use', 'account_deletion')),
  title text not null,
  version text not null,
  content text not null,
  is_current boolean not null default false,
  published_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (document_type, version)
);

create unique index if not exists legal_documents_one_current_per_type
on public.legal_documents (document_type)
where is_current;

alter table public.legal_documents enable row level security;

grant select on table public.legal_documents to anon, authenticated;
grant insert, update, delete on table public.legal_documents to authenticated;

drop policy if exists "Legal documents readable" on public.legal_documents;
create policy "Legal documents readable"
on public.legal_documents
for select
to public
using (is_current = true);

drop policy if exists "Staff can manage legal documents" on public.legal_documents;
create policy "Staff can manage legal documents"
on public.legal_documents
for all
to authenticated
using (public.user_role() in ('admin'::public.user_role, 'manager'::public.user_role))
with check (public.user_role() in ('admin'::public.user_role, 'manager'::public.user_role));

insert into public.legal_documents (document_type, title, version, content, is_current)
values
  (
    'privacy_policy',
    'Политика конфиденциальности',
    '2026-05-30',
    'MagicMusicCRM обрабатывает данные аккаунта, профильные данные, контактный телефон, сообщения, вложения, уведомления и технические данные устройства только для работы CRM, коммуникации со школой, поддержки, безопасности и выполнения юридических обязанностей. Данные хранятся в Supabase/Firebase и удаляются или обезличиваются по запросу, если закон не требует сохранения отдельных записей.',
    true
  ),
  (
    'terms_of_use',
    'Пользовательское соглашение',
    '2026-05-30',
    'Используя MagicMusicCRM, пользователь подтверждает, что предоставляет корректные данные, использует приложение только для взаимодействия со школой Magic Music и не передает доступ третьим лицам. Администрация может ограничить доступ при нарушении правил, угрозах безопасности или злоупотреблении сервисом.',
    true
  ),
  (
    'account_deletion',
    'Удаление аккаунта',
    '2026-05-30',
    'Пользователь может запросить удаление аккаунта внутри приложения. Запрос фиксируется немедленно, после чего администрация удаляет или обезличивает данные аккаунта, кроме информации, которую необходимо сохранить по закону, бухгалтерским или антифрод-основаниям.',
    true
  )
on conflict (document_type, version) do update
set title = excluded.title,
    content = excluded.content,
    is_current = excluded.is_current,
    published_at = public.legal_documents.published_at;

create table if not exists public.legal_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  document_id uuid not null references public.legal_documents(id) on delete restrict,
  accepted_at timestamptz not null default now(),
  accepted_version text not null,
  unique (user_id, document_id)
);

alter table public.legal_consents enable row level security;

grant select, insert on table public.legal_consents to authenticated;

drop policy if exists "Users read own legal consents" on public.legal_consents;
create policy "Users read own legal consents"
on public.legal_consents
for select
to authenticated
using (
  user_id = auth.uid()
  or public.user_role() in ('admin'::public.user_role, 'manager'::public.user_role)
);

drop policy if exists "Users insert own legal consents" on public.legal_consents;
create policy "Users insert own legal consents"
on public.legal_consents
for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.legal_documents d
    where d.id = document_id
      and d.is_current = true
      and d.version = accepted_version
  )
);

create or replace function public.accept_current_legal_documents()
returns void
language plpgsql
security invoker
set search_path = public
as $function$
begin
  if auth.uid() is null then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  insert into public.legal_consents (user_id, document_id, accepted_version)
  select auth.uid(), id, version
  from public.legal_documents
  where is_current = true
    and document_type in ('privacy_policy', 'terms_of_use', 'account_deletion')
  on conflict (user_id, document_id) do nothing;
end;
$function$;

revoke execute on function public.accept_current_legal_documents() from public, anon;
grant execute on function public.accept_current_legal_documents() to authenticated;

-- ── Account deletion request workflow ───────────────────────────────────────

create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'cancelled', 'rejected')),
  reason text,
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  processed_by uuid references public.profiles(id),
  staff_note text
);

create unique index if not exists account_deletion_one_open_request
on public.account_deletion_requests (user_id)
where status in ('pending', 'processing');

alter table public.account_deletion_requests enable row level security;

grant select, insert on table public.account_deletion_requests to authenticated;
grant update on table public.account_deletion_requests to authenticated;

drop policy if exists "Users read own deletion requests" on public.account_deletion_requests;
create policy "Users read own deletion requests"
on public.account_deletion_requests
for select
to authenticated
using (
  user_id = auth.uid()
  or public.user_role() in ('admin'::public.user_role, 'manager'::public.user_role)
);

drop policy if exists "Users insert own deletion request" on public.account_deletion_requests;
create policy "Users insert own deletion request"
on public.account_deletion_requests
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "Staff update deletion requests" on public.account_deletion_requests;
create policy "Staff update deletion requests"
on public.account_deletion_requests
for update
to authenticated
using (public.user_role() in ('admin'::public.user_role, 'manager'::public.user_role))
with check (public.user_role() in ('admin'::public.user_role, 'manager'::public.user_role));

create or replace function public.request_account_deletion(p_reason text default null)
returns uuid
language plpgsql
security invoker
set search_path = public
as $function$
declare
  v_request_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  insert into public.account_deletion_requests (user_id, reason)
  values (auth.uid(), nullif(trim(coalesce(p_reason, '')), ''))
  on conflict (user_id)
  where status in ('pending', 'processing')
  do update set reason = coalesce(excluded.reason, public.account_deletion_requests.reason)
  returning id into v_request_id;

  return v_request_id;
end;
$function$;

revoke execute on function public.request_account_deletion(text) from public, anon;
grant execute on function public.request_account_deletion(text) to authenticated;

-- ── Release gate status for Flutter router ──────────────────────────────────

create or replace function public.get_release_gate_status()
returns jsonb
language sql
security invoker
set search_path = public
as $function$
  with current_docs as (
    select id
    from public.legal_documents
    where is_current = true
      and document_type in ('privacy_policy', 'terms_of_use', 'account_deletion')
  ),
  accepted_docs as (
    select lc.document_id
    from public.legal_consents lc
    where lc.user_id = auth.uid()
  )
  select jsonb_build_object(
    'role', coalesce((select p.role::text from public.profiles p where p.id = auth.uid()), 'client'),
    'profileComplete', exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.profile_completed_at is not null
        and nullif(trim(coalesce(p.first_name, '')), '') is not null
        and nullif(trim(coalesce(p.last_name, '')), '') is not null
        and nullif(trim(coalesce(p.phone, '')), '') is not null
    ),
    'legalAccepted', not exists (
      select 1
      from current_docs d
      where not exists (
        select 1
        from accepted_docs a
        where a.document_id = d.id
      )
    ),
    'deletionPending', exists (
      select 1
      from public.account_deletion_requests adr
      where adr.user_id = auth.uid()
        and adr.status in ('pending', 'processing')
    )
  );
$function$;

revoke execute on function public.get_release_gate_status() from public, anon;
grant execute on function public.get_release_gate_status() to authenticated;

-- ── Personal administration chat contract ───────────────────────────────────

create table if not exists public.admin_chat_threads (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz,
  unique (client_id)
);

alter table public.admin_chat_threads enable row level security;

grant select, insert, update on table public.admin_chat_threads to authenticated;

drop policy if exists "Users read own admin chat thread" on public.admin_chat_threads;
create policy "Users read own admin chat thread"
on public.admin_chat_threads
for select
to authenticated
using (
  client_id = auth.uid()
  or public.user_role() in ('admin'::public.user_role, 'manager'::public.user_role)
);

drop policy if exists "Users create own admin chat thread" on public.admin_chat_threads;
create policy "Users create own admin chat thread"
on public.admin_chat_threads
for insert
to authenticated
with check (client_id = auth.uid());

drop policy if exists "Staff update admin chat thread" on public.admin_chat_threads;
create policy "Staff update admin chat thread"
on public.admin_chat_threads
for update
to authenticated
using (public.user_role() in ('admin'::public.user_role, 'manager'::public.user_role))
with check (public.user_role() in ('admin'::public.user_role, 'manager'::public.user_role));

create or replace function public.ensure_admin_chat_thread()
returns uuid
language plpgsql
security invoker
set search_path = public
as $function$
declare
  v_thread_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  insert into public.admin_chat_threads (client_id)
  values (auth.uid())
  on conflict (client_id) do update
    set client_id = excluded.client_id
  returning id into v_thread_id;

  return v_thread_id;
end;
$function$;

revoke execute on function public.ensure_admin_chat_thread() from public, anon;
grant execute on function public.ensure_admin_chat_thread() to authenticated;

-- ── Read-only announcements for clients ─────────────────────────────────────

drop policy if exists "Channels readable by authenticated" on public.channels;
create policy "Channels readable by authenticated"
on public.channels
for select
to authenticated
using (true);

drop policy if exists "Channel posts readable by authenticated" on public.channel_posts;
create policy "Channel posts readable by authenticated"
on public.channel_posts
for select
to authenticated
using (
  exists (
    select 1
    from public.channels c
    where c.id = channel_id
  )
);

insert into public.channels (name, description)
select 'Объявления', 'Официальные объявления школы Magic Music'
where not exists (
  select 1 from public.channels where name = 'Объявления'
);

commit;
