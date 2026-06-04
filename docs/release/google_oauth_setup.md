# Google OAuth Setup

Дата проверки: 2026-05-30

## Supabase

Для проекта `xblpnywnlhfgofskbdxb` уже настроены:

- Flutter client `supabaseUrl`: `https://xblpnywnlhfgofskbdxb.supabase.co`
- `site_url`: `https://magicmusiccrm-legal.vercel.app/`
- `uri_allow_list`: `magiccrm://auth-callback,https://magicmusiccrm-legal.vercel.app/,https://magicmusiccrm-legal.vercel.app/*`
- Google provider включен в Supabase Auth config.
- `external_google_enabled`: `true`
- `external_google_email_optional`: `false`

## Google Cloud

Проект Google Cloud: `magicmusiccrm-42557`.

Настроено:

- Google Auth Platform создан владельцем аккаунта.
- OAuth client type: `Web application`.
- Authorized JavaScript origin: `https://magicmusiccrm-legal.vercel.app`
- Authorized redirect URI: `https://xblpnywnlhfgofskbdxb.supabase.co/auth/v1/callback`
- Publishing status: `In production`.
- Scopes: `.../auth/userinfo.email`, `.../auth/userinfo.profile`, `openid`.

Публичные URL для OAuth consent:

- Homepage: `https://magicmusiccrm-legal.vercel.app/`
- Privacy Policy: `https://magicmusiccrm-legal.vercel.app/privacy/`
- Terms: `https://magicmusiccrm-legal.vercel.app/terms/`
- Account deletion: `https://magicmusiccrm-legal.vercel.app/account-deletion/`

## Проверка

Проверено 2026-05-30:

- Supabase OAuth endpoint возвращает `302` на `accounts.google.com`.
- OAuth request использует callback `https://xblpnywnlhfgofskbdxb.supabase.co/auth/v1/callback`.
- Client ID в Supabase Auth совпадает с созданным Google OAuth client.
- `workers.dev` proxy не используется для Supabase Auth/OAuth: он может отдать HTML Google Sign-In под proxy-доменом и сломать кнопку `Далее`.

Остальная ручная проверка перед релизом:

1. Выйти из приложения.
2. Нажать `Войти через Google`.
3. Завершить OAuth.
4. Проверить, что приложение получает session, затем показывает onboarding, legal consent и client dashboard.
