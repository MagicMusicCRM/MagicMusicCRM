# Resend SMTP and Email OTP Setup

Дата: 2026-06-05

## Цель

Перевести email-вход с Magic Link на одноразовые коды. В приложении используется Supabase `signInWithOtp` + `verifyOTP`.

## Supabase Auth SMTP

Настроить в Supabase Dashboard: `Authentication` -> `Emails` -> `SMTP Settings`.

- Host: `smtp.resend.com`
- Port: `587`
- Username: `resend`
- Password: Resend API key
- Sender email: подтвержденный домен/адрес Resend
- Sender name: `Magic Music CRM`

После включения custom SMTP проверить лимит отправки. У Supabase для custom SMTP стартовый лимит может быть низким, его нужно поднять перед production.

## Supabase OTP length

Настроить в Supabase Dashboard: `Authentication` -> `Providers` -> `Email`.

- OTP length: `6`
- OTP type: numeric/token code, not magic-link-only email
- Email template must render `{{ .Token }}`

Resend не генерирует OTP самостоятельно: он доставляет письмо, которое формирует Supabase Auth. Поэтому 6-значный формат задается в Supabase Auth settings, а приложение принимает только 6 цифр.

## Email templates

Email OTP используется в трех местах:

- `Confirm signup` - подтверждение регистрации через код.
- `Magic Link` - код после успешного входа по email+паролю, если пользователь включил `Email-код для входа` в настройках.

В обоих шаблонах вместо `{{ .ConfirmationURL }}` должен использоваться `{{ .Token }}`.

Минимальный текст:

```text
Ваш код входа в Magic Music CRM: {{ .Token }}
```

В шаблоне не должно быть единственной рабочей инструкцией `{{ .ConfirmationURL }}`, иначе Supabase продолжит отправлять Magic Link.

## SMTP credentials

Для Resend SMTP:

- Username: `resend`
- Password: Resend API key

Если API key был опубликован в чате, его нужно отозвать в Resend и создать новый.

## Проверка

1. Открыть приложение.
2. Создать аккаунт через email+пароль.
3. Проверить, что письмо регистрации приходит через Resend и содержит 6-значный код.
4. Ввести код на экране `/email-otp`.
5. Проверить, что создается Supabase session и пользователь попадает в onboarding/legal/dashboard.
6. В профиле открыть `Способы входа`, включить `Email-код для входа`.
7. Выйти и войти по email+паролю.
8. Проверить, что приложение запрашивает 6-значный код из письма перед входом.
