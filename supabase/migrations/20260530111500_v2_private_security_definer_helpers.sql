create schema if not exists private;

grant usage on schema private to authenticated;

create or replace function private.user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function private.is_group_member(_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.group_chat_members
    where group_chat_id = _group_id
      and user_id = auth.uid()
  );
$$;

create or replace function private.is_group_member_v2(_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.group_chat_members
    where group_chat_id = _group_id
      and user_id = auth.uid()
  );
$$;

revoke all on function private.user_role() from public, anon;
revoke all on function private.is_group_member(uuid) from public, anon;
revoke all on function private.is_group_member_v2(uuid) from public, anon;

grant execute on function private.user_role() to authenticated;
grant execute on function private.is_group_member(uuid) to authenticated;
grant execute on function private.is_group_member_v2(uuid) to authenticated;

do $$
declare
  p record;
  next_qual text;
  next_check text;
  statement text;
begin
  for p in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and (
        qual ilike '%user_role()%'
        or with_check ilike '%user_role()%'
        or qual ilike '%is_group_member(%'
        or with_check ilike '%is_group_member(%'
        or qual ilike '%is_group_member_v2(%'
        or with_check ilike '%is_group_member_v2(%'
      )
  loop
    next_qual := p.qual;
    next_check := p.with_check;

    if next_qual is not null then
      next_qual := replace(next_qual, 'user_role()', 'private.user_role()');
      next_qual := replace(next_qual, 'is_group_member_v2(', 'private.is_group_member_v2(');
      next_qual := replace(next_qual, 'is_group_member(', 'private.is_group_member(');
    end if;

    if next_check is not null then
      next_check := replace(next_check, 'user_role()', 'private.user_role()');
      next_check := replace(next_check, 'is_group_member_v2(', 'private.is_group_member_v2(');
      next_check := replace(next_check, 'is_group_member(', 'private.is_group_member(');
    end if;

    statement := format(
      'alter policy %I on %I.%I',
      p.policyname,
      p.schemaname,
      p.tablename
    );

    if next_qual is not null then
      statement := statement || format(' using (%s)', next_qual);
    end if;

    if next_check is not null then
      statement := statement || format(' with check (%s)', next_check);
    end if;

    execute statement;
  end loop;
end $$;

create or replace function public.get_recent_chats_v3(
  p_user_id uuid,
  p_is_staff boolean
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
    result jsonb;
    v_is_staff boolean;
begin
    if auth.uid() is null or p_user_id is distinct from auth.uid() then
        raise exception 'not authorized' using errcode = '42501';
    end if;

    select private.user_role() in ('admin'::public.user_role, 'manager'::public.user_role)
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
$$;

revoke execute on function public.user_role() from public, anon, authenticated;
revoke execute on function public.is_group_member(uuid) from public, anon, authenticated;
revoke execute on function public.is_group_member_v2(uuid) from public, anon, authenticated;
