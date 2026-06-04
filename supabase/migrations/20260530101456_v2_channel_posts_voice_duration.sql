alter table public.channel_posts
  add column if not exists voice_duration_ms integer;
