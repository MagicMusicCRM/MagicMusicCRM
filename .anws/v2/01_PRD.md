# 01_PRD — MagicMusicCRM Publication Readiness v2

**Status**: Draft / Checkpoint 1  
**Version**: v2.0.0-draft  
**Date**: 2026-05-30  
**Owner**: Magic Music School  
**Previous baseline**: `.anws/v1`

---

## 1. Цель версии

Подготовить MagicMusicCRM к публикации в Google Play и App Store через безопасную auth-first регистрацию, исправление модели коммуникаций, legal consent, account deletion, hardening Supabase и выпускные quality gates.

Версия v2 не является косметическим релизом. Это публикационный релиз, где безопасность Supabase, приватность данных и соответствие правилам магазинов имеют приоритет над новыми CRM-функциями.

## 2. Контекст и источники требований

- Пользовательский запрос: полная проверка перед Google Play, исправление admin/global chat, регистрация через Google Account, проверка Supabase, legal consent, удаление аккаунта, security по всем контурам.
- Локальный audit/probe: `.anws/v1/00_PROBE_REPORT.md`.
- Security scan: `C:\Users\potyl\AppData\Local\Temp\codex-security-scans\MagicMusicCRM\2a38b85_20260530_120237\report.md`.
- Google Play User Data policy: https://support.google.com/googleplay/android-developer/answer/10144311
- Google Play account deletion requirements: https://support.google.com/googleplay/android-developer/answer/13327111
- Apple account deletion guidance: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Supabase Google OAuth docs: https://supabase.com/docs/guides/auth/social-login/auth-google

## 3. Целевые роли

- **Новый пользователь**: входит через Google Account, подтверждает consent, заполняет ФИО и телефон, получает роль `client`.
- **Клиент / студент / родитель**: видит свой профиль, расписание, подписки, домашние задания, сообщения с администрацией и разрешенные объявления.
- **Администратор**: управляет пользователями, ролями, consent/legal документами, удалением аккаунтов и коммуникациями.
- **Менеджер**: работает с лидами, клиентами, задачами, финансами и коммуникациями в рамках выданной роли.
- **Преподаватель**: видит только назначенных студентов, расписание, прогресс и разрешенные чаты.
- **Compliance operator**: отвечает за privacy policy, data safety, deletion SLA и выпускные проверки.

## 4. Product Scope

### In Scope

- Google OAuth sign-in/sign-up через Supabase Auth.
- Post-auth onboarding: ФИО, телефон, согласие с Privacy Policy/Terms, consent version.
- Блокировка доступа к CRM до завершения обязательного onboarding.
- Исправление admin/global chat для новых пользователей.
- Разделение личного чата с администрацией и глобальных объявлений.
- Удаление аккаунта из приложения и внешний web deletion request path для Google Play.
- Privacy Policy, Terms, Consent UI, legal document versioning.
- Supabase hardening: RLS, functions, views, storage, Edge Functions, role model.
- Release gates для Android/iOS: анализатор, тесты, signing, permissions, privacy manifests/usage strings, Data Safety/App Privacy inputs.
- Минимальные security regression tests для критичных RLS и auth flows.

### Non-Goals

- Не переписывать весь CRM с нуля.
- Не добавлять новые продажи/финансы/учебные функции сверх publication readiness.
- Не внедрять отдельный enterprise SSO, Apple Sign In или SMS OTP в рамках первого v2 релиза.
- Не автоматизировать юридическое заключение: тексты политик должны пройти проверку владельцем/юристом.
- Не чинить desktop updater/installer как публикационный блокер мобильного релиза, кроме явных security-risk участков.

## 5. Success Metrics

- 0 critical/high findings без решения или documented exception перед релизной сборкой.
- `flutter analyze` завершается без error-level issues.
- `flutter test` покрывает auth/onboarding, account deletion entrypoint, chat visibility и ключевые RLS contracts.
- Новый пользователь после Google OAuth попадает в onboarding, а не в CRM.
- Новый пользователь после onboarding видит личный чат `Администрация`.
- Обычный `client` не может изменить свою роль, прочитать чужой PII, вызвать staff-only RPC или прочитать чужие private media.
- Android release build не использует debug signing.
- В приложении доступны Privacy Policy, Terms, consent history/current acceptance и удаление аккаунта.
- Для Google Play есть публичный URL удаления аккаунта и Data Safety disclosures, согласованные с реальным сбором данных.

## 6. Functional Requirements

### [REQ-AUTH-001] Google Account вход и регистрация

**Priority**: P0  
**Value**: новый пользователь может создать аккаунт без email/password формы и без staff-role injection.  
**Affected systems**: Flutter auth UI, Supabase Auth, Android/iOS OAuth config, deep links.

**Acceptance Criteria**

- Given пользователь не авторизован, When он нажимает `Войти через Google`, Then запускается Supabase OAuth для Google.
- Given OAuth успешен, When Supabase возвращает session, Then пользователь получает роль `client` и не может задать `admin/manager/teacher` через metadata.
- Given пользователь уже авторизован, When приложение открывается повторно, Then session восстанавливается без повторного входа.
- Given OAuth callback содержит неожиданный host/path/state, When приложение его получает, Then callback отклоняется и полный URI не логируется.

**Autonomous Test**

- Widget/integration test для Google button routing.
- Supabase RLS/SQL test: signup metadata with `role=admin` не создает staff profile.
- Static config check: Android/iOS OAuth callback configured.

### [REQ-AUTH-002] Обязательный onboarding после входа

**Priority**: P0  
**Value**: аккаунт создается сначала, персональные данные запрашиваются только после авторизации и согласия.  
**Affected systems**: router, profile service, onboarding UI, Supabase `profiles`.

**Acceptance Criteria**

- Given пользователь вошел через Google впервые, When profile incomplete, Then он видит onboarding screen.
- Given onboarding открыт, When пользователь не указал ФИО или телефон, Then продолжить нельзя.
- Given телефон указан в неверном формате, When пользователь сохраняет, Then отображается русская ошибка валидации.
- Given onboarding завершен, When пользователь открывает приложение, Then он попадает на роль-appropriate dashboard.

**Autonomous Test**

- Router tests for `profile_completed=false`.
- Unit tests for phone/name validation.
- Supabase test: клиент может обновить только разрешенные profile fields, но не `role`.

### [REQ-LEGAL-001] Consent gate и legal документы

**Priority**: P0  
**Value**: пользователь явно принимает правила обработки данных до доступа к CRM.  
**Affected systems**: legal screens, profile/onboarding, Supabase consent tables, settings.

**Acceptance Criteria**

- Given пользователь проходит onboarding, When current legal version не принята, Then приложение показывает Privacy Policy и Terms acceptance.
- Given пользователь не поставил явное согласие, When он нажимает продолжить, Then доступ к CRM закрыт.
- Given legal version обновилась, When пользователь входит, Then он видит re-consent flow до продолжения.
- Given пользователь открыл настройки, When выбирает legal раздел, Then видит текущую Privacy Policy, Terms и дату принятия.

**Autonomous Test**

- Widget tests for affirmative checkbox/toggle.
- DB tests for immutable consent audit row.
- Golden/static check: все visible UI strings на русском.

### [REQ-LEGAL-002] Удаление аккаунта

**Priority**: P0  
**Value**: пользователь и магазины получают понятный путь удаления аккаунта и связанных данных.  
**Affected systems**: settings/profile UI, Supabase Edge Function/RPC, auth admin backend, public web page.

**Acceptance Criteria**

- Given пользователь авторизован, When открывает настройки аккаунта, Then видит `Удалить аккаунт`.
- Given пользователь подтверждает удаление, When запрос принят, Then аккаунт помечается как `pending_deletion` или удаляется согласно backend flow без service-role key на клиенте.
- Given deletion request accepted, When пользователь возвращается в приложение, Then он видит статус удаления или logout.
- Given пользователь удалил приложение, When открывает публичный deletion URL, Then может запросить удаление аккаунта без повторной установки приложения.
- Given часть данных удерживается по законной причине, When пользователь читает Privacy Policy, Then retention clearly disclosed.

**Autonomous Test**

- Edge/RPC tests: only owner can request own deletion.
- Negative test: client cannot delete another account.
- Store checklist includes web deletion URL.

### [REQ-CHAT-001] Личный чат с администрацией для каждого пользователя

**Priority**: P0  
**Value**: новый пользователь всегда имеет понятный канал связи с администрацией.  
**Affected systems**: messenger UI, chat model, Supabase RLS, realtime providers.

**Draft assumption**: под текущим запросом `глобальный чат с администраторами` понимается личный чат `Администрация` между пользователем и staff, а не единая общая комната всех пользователей.

**Acceptance Criteria**

- Given новый `client` завершил onboarding, When открывает мессенджер, Then видит чат `Администрация`.
- Given пользователь пишет в `Администрация`, When сообщение сохраняется, Then staff видит его в staff inbox.
- Given другой client существует, When он открывает свой чат `Администрация`, Then он не видит сообщения первого client.
- Given staff отвечает, When client получает realtime update, Then сообщение появляется в том же личном чате.

**Autonomous Test**

- RLS tests: client A cannot read client B admin chat.
- Integration test: new user admin chat appears after onboarding.
- Realtime provider test for subscription status and empty-state.

### [REQ-CHAT-002] Глобальные объявления отдельно от личного чата

**Priority**: P1  
**Value**: администрация может отправлять announcements без смешения с приватными direct messages.  
**Affected systems**: messenger UI, announcements/channel tables, notification service, RLS.

**Acceptance Criteria**

- Given admin creates announcement, When client opens messenger, Then sees read-only `Объявления`.
- Given client opens `Объявления`, When tries to send message, Then input is disabled.
- Given announcement targets all clients, When new user joins after publication, Then visibility follows defined retention policy.

**Autonomous Test**

- RLS tests: client read allowed, client write denied.
- UI test: no send composer in read-only channel.

### [REQ-SEC-001] Supabase role and RLS hardening

**Priority**: P0  
**Value**: backend, not UI, enforces all access decisions.  
**Affected systems**: profiles, roles, RLS policies, security-definer functions/views, storage, Edge Functions.

**Acceptance Criteria**

- Given authenticated `client`, When tries to update `profiles.role`, Then request is denied.
- Given signup metadata contains staff role, When trigger creates profile, Then role remains `client`.
- Given anon user calls `get_recent_chats_v3`, When request is sent, Then access is denied.
- Given authenticated user selects profiles, When not self/staff-authorized, Then PII and FCM token are not exposed.
- Given storage object belongs to another user/chat, When user tries read/delete/update, Then request is denied.
- Given notification function is called by non-staff, When userIds are supplied, Then function rejects it.

**Autonomous Test**

- Supabase SQL/RLS tests for anon/client/staff matrix.
- Edge Function tests for authorization and no service credential in source bundle.
- Policy advisor check: no unresolved ERROR-level security advisors.

### [REQ-REL-001] Android/iOS publication readiness gates

**Priority**: P0  
**Value**: релиз не может быть собран с debug signing, лишними permissions или неполными privacy disclosures.  
**Affected systems**: Android Gradle/manifest, iOS Info.plist, Firebase config, CI/release scripts.

**Acceptance Criteria**

- Given release build requested, When signing config is read, Then debug signing is not used.
- Given Android manifest is inspected, When permissions are checked, Then sensitive permissions are removed or documented with user-facing need.
- Given iOS build is inspected, When photo/camera/microphone/file usage exists, Then Info.plist has correct Russian/English usage strings.
- Given Data Safety/App Privacy form is prepared, When compared to code dependencies, Then Firebase Analytics/Messaging, profile PII, media uploads and notifications are disclosed.

**Autonomous Test**

- Static build config tests.
- Store checklist generated from manifest/plist/dependencies.

### [REQ-QA-001] Analyzer, tests and anti-slop gate

**Priority**: P1  
**Value**: publication branch must be maintainable and mechanically verifiable.  
**Affected systems**: all Flutter modules, tests, architecture docs.

**Acceptance Criteria**

- Given `flutter analyze` runs, When release gate executes, Then no error-level issues remain.
- Given `flutter test` runs, When test suite executes, Then auth/onboarding/legal/chat/security tests pass.
- Given code review scans UI/provider layers, When direct Supabase call is found in widget build/event handler, Then task is opened to move it into `Supa*` service or provider.
- Given visible UI text is added, When review runs, Then text is Russian.

**Autonomous Test**

- Analyzer and tests in CI/local release script.
- Static grep rule for direct Supabase calls in presentation widgets.

## 7. Non-Functional Requirements

- **Security**: all authorization must be enforced in Supabase RLS/functions/storage, not only Flutter UI.
- **Privacy**: profile PII, FCM tokens and chat media are least-privilege by default.
- **Compliance**: privacy policy and deletion flows must match Google Play/App Store forms.
- **Performance**: onboarding and messenger first load should render within 2 seconds on a typical current Android device on normal network.
- **Observability**: sensitive tokens, deep-link auth material and notification payloads must not be logged in production.
- **Localization**: all UI strings visible to users are Russian for this release.

## 8. Edge Cases

- OAuth succeeds but profile creation trigger fails.
- User closes app halfway through onboarding.
- User accepts old legal version, then legal version changes.
- Account deletion requested while user has active subscription/payment obligations.
- User changes Google account email after registration.
- Staff role revoked while app session is active.
- New user has no messages yet but must still see `Администрация`.
- Announcement created before user registration.
- Attachment URL points outside Supabase storage.
- Push token exists for deleted/pending-deletion account.

## 9. Ambiguity Scan

| Dimension | Status | Notes |
|---|---|---|
| Границы функций | Clear | Publication readiness scope defined. |
| Модель данных | Partial | Detailed schema will be finalized in architecture/design. |
| UX и интерфейс | Clear | Required flows and empty states listed. |
| Нефункциональные требования | Clear | Security/privacy/compliance gates explicit. |
| Зависимости | Clear | Supabase, Google OAuth, Firebase, stores named. |
| Граничные случаи | Clear | Edge cases listed. |
| Компромиссы | Clear | Apple Sign In/enterprise SSO excluded from first v2. |
| Терминология | Partial | `global/admin chat` needs final user confirmation. |
| Сигналы готовности | Clear | Given/When/Then acceptance criteria included. |
| Заглушки | Clear | No TODO; only one marked draft assumption. |

## 10. Open Clarification

[NEEDS CLARIFICATION] Подтвердить модель `глобального чата`: рекомендованный вариант — личный чат `Администрация` для каждого пользователя плюс отдельный read-only канал `Объявления`.

---

## Checkpoint 1

После подтверждения этого PRD следующими шагами `/genesis` будут:

1. Обновить `.anws/v2/02_ARCHITECTURE.md`.
2. Добавить ADR по auth-first onboarding, role model, chat model, legal/account deletion и Supabase hardening.
3. Подготовить `04_SYSTEM_DESIGN/*`.
4. Сгенерировать новый `.anws/v2/05_TASKS.md` через `/blueprint`.
