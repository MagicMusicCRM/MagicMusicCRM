begin;

revoke insert on table public.profiles from public, anon, authenticated;
grant insert (id, role, first_name, last_name, phone, email, dob)
on table public.profiles to authenticated;

drop policy if exists "Profiles own client insert" on public.profiles;
create policy "Profiles own client insert"
on public.profiles
for insert
to authenticated
with check (
  id = auth.uid()
  and role = 'client'::public.user_role
);

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

  insert into public.profiles (id, role, email)
  values (
    auth.uid(),
    'client'::public.user_role,
    auth.jwt()->>'email'
  )
  on conflict (id) do nothing;

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

commit;
