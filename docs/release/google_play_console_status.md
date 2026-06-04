# Google Play Console Status

Дата проверки: 2026-05-30

Developer account: `6619197543593304172`

## Статус

Приложение создано пользователем в Google Play Console. Следующий шаг: заполнить App content, Store settings and Store listing, затем загрузить `app-release.aab`.

## Финальные идентификаторы приложения

- App name: `Magic Music CRM`
- Android package name / application ID: `magic.crm`
- Developer / operator: `ИП НАЗАРОВА НАТАЛИЯ НИКОЛАЕВНА`, `ИНН 220418439440`, `ОГРНИП 323774600172671`
- AAB for upload: `build/app/outputs/bundle/release/app-release.aab`

`magic.crm` уже совпадает с Firebase Android config и iOS Bundle ID. После первой загрузки в Google Play package name будет нельзя изменить без создания нового приложения.

## Что уже готово

- Public account deletion URL: `https://magicmusiccrm-legal.vercel.app/account-deletion/`
- Privacy Policy URL: `https://magicmusiccrm-legal.vercel.app/privacy/`
- Terms URL: `https://magicmusiccrm-legal.vercel.app/terms/`
- Google OAuth для регистрации/входа включен в Google Cloud и Supabase Auth.
- Release signing настроен через upload keystore, debug signing для release запрещен.
- Store legal/data-safety draft: `docs/release/store_data_safety_ru.md`
- Data Safety CSV for import: `docs/release/play_console/magic_music_crm_data_safety.csv`
- Current Google Play sample used for CSV structure: `docs/release/play_console/google_play_data_safety_sample_current_ru.csv`

## Что нужно заполнить в Play Console

- Privacy Policy URL: `https://magicmusiccrm-legal.vercel.app/privacy/`
- Указать account deletion URL: `https://magicmusiccrm-legal.vercel.app/account-deletion/`
- Сверить disclosures с фактическими данными приложения: email, ФИО, телефон, сообщения, вложения, push tokens, учебные/CRM-записи.
- Подробная шпаргалка: `docs/release/google_play_console_fill_values_ru.md`
- CSV для импорта в раздел Data safety: `docs/release/play_console/magic_music_crm_data_safety.csv`
