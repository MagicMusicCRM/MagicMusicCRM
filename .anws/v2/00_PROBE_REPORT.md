# 🔎 PROBE REPORT — MagicMusicCRM Pre-Publication Audit

> generated_by: /probe + nexus-mapper + runtime-inspector  
> verified_at: 2026-05-30T11:56:01+03:00  
> scope: Flutter app, Supabase project, Android/iOS publication readiness, legal/security gaps  
> verdict: **НЕ ГОТОВО К ПУБЛИКАЦИИ**

---

## 1. Контекст

Запрос расширяет текущую `.anws/v1`: нужно проверить приложение перед Google Play, исправить глобальный чат с администраторами, добавить регистрацию через Google Account с последующим сбором ФИО/телефона, проверить Supabase на AI Slop и функциональность, добавить privacy/legal consent и обязательную возможность удаления аккаунта, затем провести security review.

Текущий `05_TASKS.md` содержит активную задачу про PUSH-уведомления (`T-NT.2`). Новые требования существенно шире и меняют архитектуру auth/security/compliance, поэтому после probe нужен новый архитектурный цикл, а не прямой `/forge`.

---

## 2. Быстрая Карта Системы

- Flutter app: 84 файла в `lib/`.
- Tests: 1 файл в `test/`.
- AST raw scan: 207 supported files, 47,702 lines, 0 parse errors.
- Supabase project: `xblpnywnlhfgofskbdxb`, region `eu-central-2`, Postgres `17.6.1.063`.
- Edge Functions: `send-notification`, active, `verify_jwt=true`.
- `.nexus-map/` создана как база знаний для последующих сессий.

---

## 3. Проверки Tooling

| Проверка | Результат | Вывод |
|---|---:|---|
| `flutter test` | pass | Покрытие незначимое: placeholder-тест. |
| `flutter analyze` | fail | 515 issues; есть hard errors. |
| Supabase advisors | fail | Security + performance warnings/errors. |
| Android release config | fail | Release signing использует debug config. |
| Legal/account deletion | fail | Реализованных экранов/политик/consent flow нет. |

### Блокеры компиляции/анализа

- `lib/features/manager/presentation/widgets/leads_widget.dart`: отсутствует `package:flutter/material.dart`, из-за чего не определены `Widget`, `Color`, `BuildContext`, `Container` и другие типы.
- `lib/features/manager/presentation/widgets/manage_statuses_dialog.dart`: аналогичная проблема с Material import.
- `lib/core/providers/chat_providers.dart`: сравнение `RealtimeSubscribeStatus` со строкой `'SUBSCRIBED'`.

---

## 4. Auth / Onboarding

### Найдено

- `login_screen.dart` использует только `signInWithPassword`.
- `registration_screen.dart` использует только `signUp(email, password)` и передает только `full_name`.
- Google OAuth в UI не реализован.
- После регистрации нет обязательного onboarding-шагa для ФИО и телефона.
- Нет фиксации согласия с privacy policy / terms.

### Supabase-риски

Функция `create_profile_for_new_user()` создает профиль из `raw_user_meta_data`. Критично: `role` берется из пользовательских metadata:

```sql
COALESCE((NEW.raw_user_meta_data->>'role')::public.user_role, 'client')
```

`raw_user_meta_data` пользователь может менять, поэтому это нельзя использовать для авторизации или назначения роли. Это потенциальная эскалация прав до `admin/manager/teacher`, если не закрыто дополнительными ограничениями.

---

## 5. Messenger / “Глобальный” Чат

### Вероятная причина проблемы

- Клиентский список всегда добавляет синтетический `admin_chat`, но сообщения загружаются фильтром `sender_id == user OR receiver_id == user`.
- Сообщения администраторов с `receiver_id IS NULL` не попадают в клиентскую выборку, если клиент не является `sender_id/receiver_id`.
- RLS policy `Messages visibility` также не разрешает клиенту видеть admin broadcast с `receiver_id IS NULL`.
- Групповые чаты показываются только если есть запись в `group_chat_members`; авто-добавления новых пользователей в глобальный чат не найдено.
- Staff-list показывает нового клиента только при наличии `lastMsg`, поэтому новый клиент без сообщений может не появляться у администраторов.

### Вывод

Нужно выбрать модель:

1. Долговременный системный чат `school/admin` с отдельной сущностью и membership.
2. Персональные direct threads client-admin.
3. Broadcast/channel read-only модель.

Текущий код смешивает эти модели, из-за чего visibility зависит от случайных `receiver_id`, RLS и локальных фильтров.

---

## 6. Supabase Security Findings

### Critical

- `create_profile_for_new_user()` доверяет `raw_user_meta_data.role`.
- `update_last_seen(user_id uuid)` — security definer и обновляет произвольный `profiles.id = user_id`.
- `get_recent_chats_v3(p_user_id, p_is_staff)` — security definer, принимает caller-supplied `p_user_id` и `p_is_staff`.
- Security-definer functions исполняемы `anon`/`authenticated` для большого списка функций.
- Public views работают как security definer: `v_teacher_students`, `v_student_upcoming_lessons`, `v_student_teachers`, `v_student_lessons_all`, `student_balances`.
- Storage buckets `avatars` и `chat-attachments` публичные; object policies слишком широкие.

### High

- `profiles` policy: authenticated users can select all profiles.
- `messages` policy не соответствует ожидаемой модели глобального/admin-чата.
- Function `search_path` mutable для `update_last_seen`, `handle_updated_at`, `get_recent_chats_v3`.
- Leaked password protection disabled in Supabase Auth.
- Multiple permissive RLS policies and many RLS initplan performance warnings.

---

## 7. Store / Legal Readiness

### Android

- `android/app/build.gradle.kts`: release signing uses debug config.
- `applicationId = "magic.crm"` и TODO про уникальный application id.
- `AndroidManifest.xml`: есть `REQUEST_INSTALL_PACKAGES`, `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`; эти permissions требуют отдельного обоснования или удаления.
- Не найден `POST_NOTIFICATIONS`, хотя проект делает push.
- Deep link `magiccrm://auth-callback` помечен `autoVerify=true`, что не имеет смысла для custom scheme.

### iOS

- Не найдены обязательные privacy usage strings для возможных функций media/voice/photo.
- Не найден Google reversed client URL scheme в `Info.plist`.

### Legal

Отсутствует:

- Privacy Policy screen/link.
- Terms / User Agreement screen/link.
- Consent checkbox/gate before account creation or first app access.
- Consent version/timestamp in DB.
- Account deletion screen and backend flow.
- Data Safety/collection inventory.

---

## 8. AI Slop / Технический Долг

- 56 `lib/` файлов обращаются к Supabase напрямую, включая widgets/screens; это нарушает AGENTS.md Supa-service/Riverpod boundary.
- `test/widget_test.dart` — placeholder.
- TODO/temporary markers:
  - Android release application id/signing TODO.
  - `student_detail_screen.dart`: `TODO: Launch URL`.
  - `chat_providers.dart`: `.eq('group_chat_id', 'null')` с комментарием “might not work”.
  - `admin_overview_widget.dart`: “Groups for now”.
  - `leads_widget.dart`: TODO вынести fetching в service/provider.
- В UI остаются `boxShadow` и градиенты в нескольких местах, что частично конфликтует с Flat Magic rules.

---

## 9. Risk Matrix

| Риск | Impact | Likelihood | Severity |
|---|---:|---:|---:|
| Role escalation через user metadata | High | Medium | Critical |
| Публикация debug-signed release | High | High | Critical |
| `flutter analyze` fails | High | High | Critical |
| Account deletion отсутствует | High | High | Critical |
| Privacy/Terms consent отсутствует | High | High | Critical |
| Admin/global chat invisible for new users | Medium | High | High |
| Public storage buckets + broad policies | High | Medium | High |
| Direct Supabase calls in widgets | Medium | High | High |
| Placeholder-only tests | Medium | High | High |
| Excess Android permissions | Medium | Medium | Medium |

---

## 10. Рекомендованный Следующий Процесс

### Не начинать публикацию

Проект нужно считать blocked для Google Play до устранения compile/security/compliance блокеров.

### Запустить архитектурное обновление

Рекомендуемый путь:

1. `/genesis` для `.anws/v2`: auth model, onboarding, legal consent, deletion, chat model, Supabase security hardening.
2. `/blueprint`: разложить на задачи и волны.
3. `/forge`: реализовать быстрые блокеры и затем функциональные изменения.
4. Отдельный authorized security scan: exhaustive scan с subagents после подтверждения пользователя.

### Быстрые правки-кандидаты после подтверждения

- Починить analyzer blockers (`material.dart` imports, Realtime status enum).
- Убрать debug signing из release или настроить production keystore.
- Добавить первичный Google OAuth button + callback wiring только после согласования новой auth/onboarding схемы.
- Спроектировать Supabase migrations: безопасная profile trigger, RLS для admin chat, `security_invoker` views, storage policies, account deletion Edge Function.
