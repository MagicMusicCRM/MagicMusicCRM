# Store Data Safety / App Privacy Draft

Дата проверки: 2026-05-30

Этот документ нужен как рабочая основа для Google Play Data safety и Apple App Privacy. Финальные ответы в сторах должны совпадать с фактической опубликованной версией приложения.

## App Identity

- App name: `Magic Music CRM`
- Android package name: `magic.crm`
- Developer / operator: `ИП НАЗАРОВА НАТАЛИЯ НИКОЛАЕВНА`, `ИНН 220418439440`, `ОГРНИП 323774600172671`
- Public privacy policy: `https://magicmusiccrm-legal.vercel.app/privacy/`
- Public account deletion: `https://magicmusiccrm-legal.vercel.app/account-deletion/`

## Collected Data

| Категория | Данные | Назначение |
|---|---|---|
| Account info | Email, ФИО, номер телефона | Регистрация, профиль пользователя, связь с администрацией |
| User content | Сообщения, вложения, голосовые сообщения | Работа личного чата `Администрация`, групповых чатов и `Объявлений` |
| Photos / files / audio | Аватар, изображения, документы, voice messages | Профиль и вложения в чатах |
| App activity | CRM-записи, занятия, задачи, оплаты, прогресс и другой пользовательский CRM-контент | Операционная работа школы и отображение данных пользователю по роли |
| Device or other IDs | Firebase Cloud Messaging token, Supabase auth/session identifiers, Firebase installation/device identifiers | Push-уведомления, безопасность сессии, доставка сервисных сообщений |

## Sharing / Processing

- Data is processed by Supabase for auth, database, storage, RLS and Edge Functions.
- Push notifications are delivered through Firebase Cloud Messaging.
- Firebase Analytics is not included in the current Android release build; Firebase is used for Cloud Messaging.
- Public legal pages are hosted on Vercel.
- Data is not sold and is not used for advertising profiling.

## Security Practices

- Network transport uses HTTPS/TLS.
- Private chat attachments are stored in a private Supabase bucket and are accessed by signed URLs.
- User role escalation is server-owned; clients cannot update `profiles.role`.
- FCM token writes are guarded by RPC/RLS.
- Account deletion is available in app and through the public deletion URL.

## Store Answers Baseline

- Data collection: yes.
- Data sharing in Google Play terms: no, if Supabase/Firebase/Vercel act only as service providers/processors under Google's exemption and data is not sold or used for advertising. The privacy policy still discloses these processors.
- Data encryption in transit: yes.
- User can request account deletion: yes.
- Advertising ID: not used in current release.
- Approximate/precise location: not used in current release.
- Contacts, calendar, health, SMS/call logs: not used in current release.

## Official References

- Google Play User Data policy: `https://support.google.com/googleplay/android-developer/answer/10144311`
- Google Play Data safety form: `https://support.google.com/googleplay/android-developer/answer/10787469`
- Apple account deletion guidance: `https://developer.apple.com/support/offering-account-deletion-in-your-app/`
