begin;

-- Store Storage objects as stable storage references instead of absolute
-- Supabase URLs. The Flutter client resolves these references through the
-- currently configured Supabase host, e.g. https://api.magic-music.org.

update public.profiles
set avatar_url = regexp_replace(
  avatar_url,
  '^https://(xblpnywnlhfgofskbdxb\.supabase\.co|api\.magic-music\.org|xbnywnlhfgofskbdxb\.supabase\.co)/storage/v1/object/(public|sign)/avatars/',
  'storage://avatars/'
)
where avatar_url ~ '^https://(xblpnywnlhfgofskbdxb\.supabase\.co|api\.magic-music\.org|xbnywnlhfgofskbdxb\.supabase\.co)/storage/v1/object/(public|sign)/avatars/';

update public.group_chats
set avatar_url = regexp_replace(
  avatar_url,
  '^https://(xblpnywnlhfgofskbdxb\.supabase\.co|api\.magic-music\.org|xbnywnlhfgofskbdxb\.supabase\.co)/storage/v1/object/(public|sign)/avatars/',
  'storage://avatars/'
)
where avatar_url ~ '^https://(xblpnywnlhfgofskbdxb\.supabase\.co|api\.magic-music\.org|xbnywnlhfgofskbdxb\.supabase\.co)/storage/v1/object/(public|sign)/avatars/';

update public.channels
set avatar_url = regexp_replace(
  avatar_url,
  '^https://(xblpnywnlhfgofskbdxb\.supabase\.co|api\.magic-music\.org|xbnywnlhfgofskbdxb\.supabase\.co)/storage/v1/object/(public|sign)/avatars/',
  'storage://avatars/'
)
where avatar_url ~ '^https://(xblpnywnlhfgofskbdxb\.supabase\.co|api\.magic-music\.org|xbnywnlhfgofskbdxb\.supabase\.co)/storage/v1/object/(public|sign)/avatars/';

update public.messages
set attachment_url = regexp_replace(
  attachment_url,
  '^https://(xblpnywnlhfgofskbdxb\.supabase\.co|api\.magic-music\.org|xbnywnlhfgofskbdxb\.supabase\.co)/storage/v1/object/(public|sign)/chat-attachments/',
  'storage://chat-attachments/'
)
where attachment_url ~ '^https://(xblpnywnlhfgofskbdxb\.supabase\.co|api\.magic-music\.org|xbnywnlhfgofskbdxb\.supabase\.co)/storage/v1/object/(public|sign)/chat-attachments/';

update public.system_settings
set value = to_jsonb(regexp_replace(
  value #>> '{}',
  '^https://(xblpnywnlhfgofskbdxb\.supabase\.co|api\.magic-music\.org|xbnywnlhfgofskbdxb\.supabase\.co)/storage/v1/object/(public|sign)/avatars/',
  'storage://avatars/'
))
where key = 'admin_chat_avatar_url'
  and jsonb_typeof(value) = 'string'
  and (value #>> '{}') ~ '^https://(xblpnywnlhfgofskbdxb\.supabase\.co|api\.magic-music\.org|xbnywnlhfgofskbdxb\.supabase\.co)/storage/v1/object/(public|sign)/avatars/';

commit;
