# Supabase Email Templates

Дата: 2026-06-05

## Confirm signup

Используется для регистрации через email+пароль. Вставить в Supabase Auth email template `Confirm signup`.

```html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Код подтверждения регистрации</title>
  <style>
    body { font-family: Arial, sans-serif; background-color: #f4f4f7; color: #1a1a1a; margin: 0; padding: 0; }
    .wrapper { width: 100%; background-color: #f4f4f7; padding: 40px 0; }
    .main { background-color: #ffffff; margin: 0 auto; width: 100%; max-width: 600px; border-radius: 12px; overflow: hidden; }
    .header { background-color: #191919; padding: 32px 20px; text-align: center; }
    .header h1 { color: #C5A059; margin: 0; font-size: 28px; font-weight: 800; }
    .content { padding: 36px 30px; text-align: center; line-height: 1.6; }
    .content h2 { color: #111827; font-size: 22px; margin: 0 0 12px; }
    .content p { color: #4B5563; font-size: 16px; margin: 0 0 24px; }
    .code { display: inline-block; letter-spacing: 8px; font-size: 32px; font-weight: 800; color: #111827; background-color: #F3EEE3; border: 1px solid #C5A059; border-radius: 10px; padding: 16px 22px; }
    .footer { text-align: center; padding: 20px; font-size: 13px; color: #6B7280; }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="main">
      <div class="header">
        <h1>Magic Music CRM</h1>
      </div>
      <div class="content">
        <h2>Подтвердите email</h2>
        <p>Введите этот код в приложении, чтобы завершить регистрацию.</p>
        <div class="code">{{ .Token }}</div>
        <p style="font-size: 14px; margin-top: 24px;">Если вы не создавали аккаунт, просто проигнорируйте это письмо.</p>
      </div>
      <div class="footer">
        © 2026 Magic Music CRM. Письмо отправлено автоматически.
      </div>
    </div>
  </div>
</body>
</html>
```

## Magic Link

Используется как email-код второго фактора после входа по email+паролю. Вставить в Supabase Auth email template `Magic Link`.

```html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Код входа</title>
  <style>
    body { font-family: Arial, sans-serif; background-color: #f4f4f7; color: #1a1a1a; margin: 0; padding: 0; }
    .wrapper { width: 100%; background-color: #f4f4f7; padding: 40px 0; }
    .main { background-color: #ffffff; margin: 0 auto; width: 100%; max-width: 600px; border-radius: 12px; overflow: hidden; }
    .header { background-color: #191919; padding: 32px 20px; text-align: center; }
    .header h1 { color: #C5A059; margin: 0; font-size: 28px; font-weight: 800; }
    .content { padding: 36px 30px; text-align: center; line-height: 1.6; }
    .content h2 { color: #111827; font-size: 22px; margin: 0 0 12px; }
    .content p { color: #4B5563; font-size: 16px; margin: 0 0 24px; }
    .code { display: inline-block; letter-spacing: 8px; font-size: 32px; font-weight: 800; color: #111827; background-color: #F3EEE3; border: 1px solid #C5A059; border-radius: 10px; padding: 16px 22px; }
    .footer { text-align: center; padding: 20px; font-size: 13px; color: #6B7280; }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="main">
      <div class="header">
        <h1>Magic Music CRM</h1>
      </div>
      <div class="content">
        <h2>Код входа</h2>
        <p>Введите этот код в приложении для завершения входа.</p>
        <div class="code">{{ .Token }}</div>
        <p style="font-size: 14px; margin-top: 24px;">Если вы не входили в аккаунт, смените пароль и сообщите администратору.</p>
      </div>
      <div class="footer">
        © 2026 Magic Music CRM. Письмо отправлено автоматически.
      </div>
    </div>
  </div>
</body>
</html>
```
