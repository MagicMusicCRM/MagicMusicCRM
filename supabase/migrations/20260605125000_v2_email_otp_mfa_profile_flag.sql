begin;

alter table public.profiles
add column if not exists email_otp_2fa_enabled boolean not null default false;

grant update (email_otp_2fa_enabled)
on table public.profiles
to authenticated;

commit;
