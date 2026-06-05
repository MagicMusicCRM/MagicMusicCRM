begin;

create or replace function public.trigger_invoke_send_notification()
returns trigger
language plpgsql
security definer
set search_path = public, vault
as $function$
declare
  v_user_ids uuid[];
  v_url text;
  v_anon_key text;
  v_dispatch_secret text;
  v_payload jsonb;
  v_target_chat_id text;
begin
  v_target_chat_id := coalesce(new.data->>'chat_id', new.data->>'sender_id');

  if new.data->>'receiver_id' is not null then
    select array_agg(id) into v_user_ids
    from (select (new.data->>'receiver_id')::uuid as id) sub
    where not exists (
      select 1
      from public.chat_preferences cp
      where cp.user_id = sub.id
        and cp.chat_id = v_target_chat_id
        and cp.is_muted = true
    );
  else
    select array_agg(p.id) into v_user_ids
    from public.profiles p
    where p.role::text = any(new.target_roles)
      and not exists (
        select 1
        from public.chat_preferences cp
        where cp.user_id = p.id
          and cp.chat_id = v_target_chat_id
          and cp.is_muted = true
      );
  end if;

  if v_user_ids is null or array_length(v_user_ids, 1) = 0 then
    return new;
  end if;

  select decrypted_secret into v_dispatch_secret
  from vault.decrypted_secrets
  where name = 'notification_dispatch_secret'
  limit 1;

  if nullif(v_dispatch_secret, '') is null then
    return new;
  end if;

  v_payload := jsonb_build_object(
    'userIds', v_user_ids,
    'title', new.data->>'title',
    'body', new.data->>'body',
    'sender_id', new.data->>'sender_id',
    'chat_id', new.data->>'chat_id',
    'receiver_id', new.data->>'receiver_id'
  );

  v_url := 'https://api.magic-music.org/functions/v1/send-notification';
  v_anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhibHBueXdubGhmZ29mc2tiZHhiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNDA5ODcsImV4cCI6MjA4ODcxNjk4N30.qRuC_TQ8rlz68fzi0geqqdbkA7ABRBEyw3GyMkMJJxg';

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon_key,
      'x-notification-dispatch-secret', v_dispatch_secret
    ),
    body := v_payload
  );

  return new;
end;
$function$;

revoke execute on function public.trigger_invoke_send_notification() from public, anon, authenticated;

commit;
