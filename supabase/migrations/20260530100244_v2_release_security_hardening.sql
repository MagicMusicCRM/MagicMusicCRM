-- MagicMusicCRM v2 release security hardening.
--
-- Intended target: staging/local Supabase first. Do not apply directly to
-- production without validating the actor matrix from `.anws/v2/05_TASKS.md`.
--
-- Covers:
-- - MMCRM-SEC-001 / MMCRM-SEC-012: role assignment and self-update hardening.
-- - MMCRM-SEC-002 / MMCRM-SEC-003: unsafe public RPC hardening.
-- - MMCRM-SEC-005: security-definer view posture.

begin;

-- 1. New profiles are always clients. User metadata is not an authorization
-- source in Supabase because raw_user_meta_data is user-editable.
create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  insert into public.profiles (id, role, first_name, last_name, phone, email, dob)
  values (
    new.id,
    'client'::public.user_role,
    new.raw_user_meta_data->>'first_name',
    new.raw_user_meta_data->>'last_name',
    new.raw_user_meta_data->>'phone',
    new.email,
    nullif(new.raw_user_meta_data->>'dob', '')::date
  )
  on conflict (id) do nothing;

  if new.email is not null then
    update public.students
    set profile_id = new.id
    where profile_id is null and email = new.email;

    update public.teachers
    set profile_id = new.id
    where profile_id is null and email = new.email;

    update public.employees
    set profile_id = new.id
    where profile_id is null and email = new.email;
  end if;

  if new.raw_user_meta_data->>'phone' is not null then
    update public.students
    set profile_id = new.id
    where profile_id is null and phone = new.raw_user_meta_data->>'phone';

    update public.teachers
    set profile_id = new.id
    where profile_id is null and phone = new.raw_user_meta_data->>'phone';

    update public.employees
    set profile_id = new.id
    where profile_id is null and phone = new.raw_user_meta_data->>'phone';
  end if;

  return new;
end;
$function$;

revoke execute on function public.create_profile_for_new_user() from public, anon, authenticated;

-- 2. Clients may update only safe self-service profile fields. Staff role
-- changes must move to a server-owned workflow/RPC, not direct table updates.
revoke update on table public.profiles from public, anon, authenticated;
grant update (first_name, last_name, phone, dob, avatar_url, fcm_token, last_seen_at)
on table public.profiles to authenticated;

drop policy if exists "Profiles updateable by own" on public.profiles;
create policy "Profiles safe self update"
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

-- 3. Keep the existing RPC signature for compatibility, but bind identity and
-- staff privilege to the JWT/session inside the function.
create or replace function public.get_recent_chats_v3(p_user_id uuid, p_is_staff boolean)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $function$
declare
    result jsonb;
    v_is_staff boolean;
begin
    if auth.uid() is null or p_user_id is distinct from auth.uid() then
        raise exception 'not authorized' using errcode = '42501';
    end if;

    select public.user_role() in ('admin'::public.user_role, 'manager'::public.user_role)
    into v_is_staff;

    with
    direct_partners as (
        select distinct on (partner_id)
            partner_id,
            last_msg_id
        from (
            select
                case when sender_id = p_user_id then receiver_id else sender_id end as partner_id,
                id as last_msg_id,
                created_at
            from public.messages
            where group_chat_id is null
              and (
                sender_id = p_user_id
                or receiver_id = p_user_id
                or (v_is_staff and receiver_id is null)
              )
            order by created_at desc
        ) sub
        where partner_id is not null or (v_is_staff and partner_id is null)
        order by partner_id, created_at desc
    ),
    my_groups as (
        select group_chat_id as id
        from public.group_chat_members
        where user_id = p_user_id
    ),
    my_channels as (
        select c.id
        from public.channels c
    ),
    combined_items as (
        select
            partner_id::text as id,
            'direct' as item_type,
            coalesce(p.first_name || ' ' || p.last_name, 'Администрация') as display_name,
            p.avatar_url,
            p.id as partner_id,
            (select row_to_json(m) from public.messages m where m.id = dp.last_msg_id) as last_message,
            (
              select count(*)::int
              from public.messages m
              where m.is_read = false
                and m.group_chat_id is null
                and m.receiver_id = p_user_id
                and m.sender_id = dp.partner_id
            ) as unread_count
        from direct_partners dp
        left join public.profiles p on p.id = dp.partner_id

        union all

        select
            g.id::text,
            'group',
            g.name,
            g.avatar_url,
            null,
            (select row_to_json(m) from public.messages m where m.group_chat_id = g.id order by created_at desc limit 1),
            0
        from public.group_chats g
        join my_groups mg on mg.id = g.id

        union all

        select
            c.id::text,
            'channel',
            c.name,
            c.avatar_url,
            null,
            (select row_to_json(m) from public.channel_posts m where m.channel_id = c.id order by created_at desc limit 1),
            0
        from public.channels c
        join my_channels mc on mc.id = c.id
    )
    select jsonb_agg(ci) into result
    from (
        select ci.*,
               cp.is_muted::boolean as is_muted,
               cp.is_pinned::boolean as is_pinned,
               cp.pinned_at as pinned_at
        from combined_items ci
        left join public.chat_preferences cp on cp.chat_id = ci.id and cp.user_id = p_user_id
        order by cp.is_pinned desc nulls last, (ci.last_message->>'created_at') desc nulls last
    ) ci;

    return coalesce(result, '[]'::jsonb);
end;
$function$;

revoke execute on function public.get_recent_chats_v3(uuid, boolean) from public, anon;
grant execute on function public.get_recent_chats_v3(uuid, boolean) to authenticated;

-- 4. Preserve the existing update_last_seen(user_id) signature for callers, but
-- ignore the caller-supplied id and update only the authenticated user's row.
create or replace function public.update_last_seen(user_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $function$
begin
  if auth.uid() is null then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  update public.profiles
  set last_seen_at = now()
  where id = auth.uid();
end;
$function$;

revoke execute on function public.update_last_seen(uuid) from public, anon;
grant execute on function public.update_last_seen(uuid) to authenticated;

alter function public.handle_updated_at() set search_path = public;

-- 5. Remove the Supabase security-definer-view advisor finding where the
-- database supports Postgres 15 security invoker views.
alter view if exists public.v_teacher_students set (security_invoker = true);
alter view if exists public.v_student_upcoming_lessons set (security_invoker = true);
alter view if exists public.v_student_teachers set (security_invoker = true);
alter view if exists public.v_student_lessons_all set (security_invoker = true);
alter view if exists public.student_balances set (security_invoker = true);

-- 6. Reduce anonymous RPC exposure for role lookup. Authenticated execution is
-- kept because existing RLS policies call public.user_role().
revoke execute on function public.user_role() from public, anon;
grant execute on function public.user_role() to authenticated;

commit;
