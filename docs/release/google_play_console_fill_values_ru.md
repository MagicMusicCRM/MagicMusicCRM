# Google Play Console Fill Values

Дата: 2026-05-30

## App identity

- Название: `Magic Music CRM`
- Package name: `magic.crm`
- Разработчик / оператор: `ИП НАЗАРОВА НАТАЛИЯ НИКОЛАЕВНА`
- ИНН: `220418439440`
- ОГРНИП: `323774600172671`
- Privacy Policy: `https://magicmusiccrm-legal.vercel.app/privacy/`
- Account deletion: `https://magicmusiccrm-legal.vercel.app/account-deletion/`
- Child safety standards: `https://magicmusiccrm-legal.vercel.app/child-safety/`
- Website: `https://magicmusiccrm-legal.vercel.app/`
- Email: `magicmusiccrm@gmail.com`
- Data Safety CSV: `docs/release/play_console/magic_music_crm_data_safety.csv`
- CSV template source: `docs/release/play_console/google_play_data_safety_sample_current_ru.csv`

## App content

| Раздел | Ответ |
|---|---|
| Privacy policy | `https://magicmusiccrm-legal.vercel.app/privacy/` |
| App access | Restricted by login. Provide a Google review account. |
| Ads | No, the app does not contain ads. |
| Content rating | Not a game; business/productivity app. Online interaction/user-generated content: yes, because chats and attachments exist. Gambling, violence, sexual content, controlled substances, horror: no. |
| Target audience | 18 and over. The app is not child-directed. |
| Child safety standards | `https://magicmusiccrm-legal.vercel.app/child-safety/`. Contact: `magicmusiccrm@gmail.com`. In-app reporting: personal chat `Администрация`. |
| Data safety | Data collection: yes. Encryption in transit: yes. Account deletion: yes. Data sold/ads: no. Sharing: no if all third-party processing remains limited to service providers/processors. |
| Government apps | No. |
| Financial features | No financial services. Lesson/payment/balance records are CRM records, not loans, banking, crypto, insurance or money transfer. |
| Health | No health, medical or fitness functionality. |

## Data Safety categories

Select these data types when available in the questionnaire:

- Personal info: name, email address, phone number, user IDs, optional date of birth if enabled in profile.
- Financial info: purchase history / other financial info only as CRM payment/balance records for lessons.
- Messages: in-app messages.
- Photos and videos: photos/images if users upload avatars or chat attachments.
- Audio: voice or sound recordings if voice messages are enabled.
- Files and docs: chat/profile/CRM attachments.
- App activity: user-generated CRM activity and other CRM actions.
- Device or other IDs: FCM token, Supabase session identifiers, Firebase installation/device identifiers.

Do not select location, contacts, SMS/call logs, health/fitness, web browsing history, advertising ID, crash logs, diagnostics or page views/taps for the current release.

## Store listing

- Default language: Russian (`ru-RU`).
- App category: Business.
- Short description: `CRM для школы Magic Music: занятия, чаты, профиль и уведомления`
- App icon: `docs/release/play_console/store_assets/app_icon_512.png`
- Feature graphic: `docs/release/play_console/store_assets/feature_graphic_1024x500.png`
- Full description:

```text
Magic Music CRM — приложение для учеников, родителей, преподавателей, менеджеров и администрации школы Magic Music.

В приложении доступны профиль пользователя, расписание и учебные данные, личный чат с администрацией, объявления, вложения и push-уведомления. Новые пользователи входят через Google Account, заполняют ФИО и номер телефона, принимают политику конфиденциальности и условия использования.

Приложение используется для внутреннего взаимодействия со школой Magic Music. Доступ к данным ограничивается ролью пользователя.
```

## App access reviewer instructions

```text
The app requires authentication.
1. Open the app.
2. Tap "Войти через Google".
3. Sign in using the Google review account provided in Play Console.
4. If onboarding is shown, enter:
   ФИО: Google Play Review
   Телефон: +79990000000
5. Accept Privacy Policy and Terms.
6. Main user areas available for review: Профиль, Администрация chat, Объявления, Удалить аккаунт.

No paid subscription, VPN, special hardware, or manual admin approval is required for the review account.
```

Create a separate Google review account and enter its email/password only inside Google Play Console.

## Remaining store assets

- Phone screenshots for Play listing.
- 512x512 high-res icon: `docs/release/play_console/store_assets/app_icon_512.png`.
- 1024x500 feature graphic: `docs/release/play_console/store_assets/feature_graphic_1024x500.png`.
- Optional 7-inch/10-inch tablet screenshots if Play Console requires them for the selected device types.

## Official references

- Google Play User Data policy: `https://support.google.com/googleplay/android-developer/answer/10144311`
- Google Play Data safety form: `https://support.google.com/googleplay/android-developer/answer/10787469`
- Google Play account deletion requirements: `https://support.google.com/googleplay/android-developer/answer/13327111`
- Google Play app access instructions: `https://support.google.com/googleplay/android-developer/answer/9859455`
- Google Play target audience and content: `https://support.google.com/googleplay/android-developer/answer/9867159`
