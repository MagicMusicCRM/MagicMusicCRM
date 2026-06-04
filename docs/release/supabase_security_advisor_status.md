# Supabase Security Advisor Status

Дата проверки: 2026-05-30

Проект: `xblpnywnlhfgofskbdxb`

## Закрыто

- `security_definer_view`: все найденные view переведены на `security_invoker`.
- `auth_leaked_password_protection`: включена HIBP-проверка leaked passwords через Supabase Auth config.
- Exposed `SECURITY DEFINER` RPC:
  - `public.user_role()`
  - `public.is_group_member(uuid)`
  - `public.is_group_member_v2(uuid)`

Helper-функции перенесены в неэкспонируемую схему `private`, RLS-политики обновлены на `private.*`, у публичных функций отозван `EXECUTE` для `anon` и `authenticated`.

## Закрыто по Storage / FCM / Edge Function

- Bucket `chat-attachments` переведен в private mode, лимит размера: 25 MB.
- Chat attachment access теперь идет через `storage://...` references и short-lived signed URLs.
- Storage policies ограничивают upload/read/delete владельцем, участником чата или staff-ролью.
- FCM tokens перенесены в `public.fcm_tokens` с RLS; client пишет токен только через `public.upsert_fcm_token(...)`.
- Privileged helper `private.upsert_fcm_token(...)` недоступен `anon`, доступен `authenticated` только через публичный wrapper.
- Edge Function `send-notification` version 14 активна, `verify_jwt=true`.
- Bundled Firebase service account больше не находится в Edge Function bundle; Firebase credential берется из Supabase secret.
- Direct anon smoke call to `send-notification` returns `403 {"error":"forbidden"}`.

## Осталось

- `extension_in_public` для `pg_net`: `ALTER EXTENSION pg_net SET SCHEMA extensions` не поддерживается самим расширением. `DROP EXTENSION` на live не выполнялся, потому что это может удалить внутренние объекты `net.*`.

Повторная live-проверка Supabase Security Advisor 2026-05-30 после Storage/FCM hardening вернула только этот `WARN`; `ERROR`-уровень пуст.

Security note: старый bundled Firebase service account key нужно считать скомпрометированным и ротировать в Firebase/Google Cloud после релиза.

## Публичные legal URL

- Privacy Policy: `https://magicmusiccrm-legal.vercel.app/privacy/`
- Terms: `https://magicmusiccrm-legal.vercel.app/terms/`
- Account deletion: `https://magicmusiccrm-legal.vercel.app/account-deletion/`
