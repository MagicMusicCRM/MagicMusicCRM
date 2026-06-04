# Журнал изменений — .anws v2

> Этот файл фиксирует микро-изменения в процессе итерации версии. Новые крупные функции или изменение архитектурных границ требуют отдельной версии через `/genesis`.

## Формат записей

- **[CHANGE]** Корректировка существующих задач через `/change`
- **[FIX]** Исправление ошибок в документации
- **[REMOVE]** Удаление контента
- **[ADD]** Добавление документов/решений версии

---

## 2026-05-30 — Инициализация

- [ADD] Создана версия `.anws/v2` как copy-and-evolve от `.anws/v1`.
- [ADD] Цель версии: pre-publication readiness, Google onboarding, legal consent, account deletion, admin/global chat model, Supabase security hardening.
- [REMOVE] Старый `05_TASKS.md` исключен из v2 до генерации нового blueprint.

## 2026-05-30 — Checkpoint 1 / PRD

- [ADD] Создан `.anws/v2/concept_model.json` с единой терминологией publication readiness, auth-first onboarding, legal consent, account deletion и chat model.
- [CHANGE] Обновлен `.anws/v2/01_PRD.md` под публикационный релиз v2.
- [ADD] Зафиксирована draft-assumption: личный чат `Администрация` для каждого пользователя плюс read-only канал `Объявления`.
- [ADD] В PRD добавлены официальные источники Google Play, Apple App Store и Supabase OAuth.

## 2026-05-30 — Checkpoint 2 / Architecture

- [CHANGE] Пользователь подтвердил модель чата: персональный `Администрация` + read-only `Объявления`.
- [ADD] Создан `.anws/v2/02_ARCHITECTURE_OVERVIEW.md`.
- [ADD] Созданы ADR-001..ADR-006 для стека, auth-first onboarding, chat model, legal/delete, Supabase hardening и store release gates.
- [ADD] Созданы system design документы: `auth_legal.md`, `supabase_security.md`, `messaging.md`, `release_compliance.md`.

## 2026-05-30 — Blueprint

- [ADD] Создан `.anws/v2/05_TASKS.md` с P0/P1 задачами подготовки релиза Google Play/App Store.
- [ADD] Определена первая `/forge`-волна: Android release config, iOS release config, analyzer hard-error cleanup.

## 2026-05-30 — Forge Wave 1 старт

- [CHANGE] Android release config больше не использует debug signing; добавлен `android/key.properties.example` и `docs/release/android_signing.md`.
- [CHANGE] Из Android manifest удалены `REQUEST_INSTALL_PACKAGES`, `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`.
- [CHANGE] iOS `Info.plist` получил `magiccrm` URL scheme и privacy usage descriptions для camera/microphone/photo library.
- [FIX] Устранены analyzer hard errors в manager widgets и realtime status comparison.
- [ADD] Создана локальная Supabase migration draft `20260530094611_v2_release_security_hardening.sql` для S1; не применялась к live DB.

## 2026-05-30 — Forge Wave 1 auth entrypoint

- [CHANGE] На экранах входа и регистрации добавлен Google OAuth entrypoint через Supabase с redirect `magiccrm://auth-callback`.
- [FIX] Deep-link обработчик больше не логирует полный callback URI и игнорирует неподходящие схемы/host.
- [NOTE] T3.1.1 остается частичной задачей до smoke-теста Google provider settings в Supabase staging.

## 2026-05-30 — Forge Wave 2 backend/app gates

- [CHANGE] Live Supabase hardening применен: role metadata больше не назначает staff role, `profiles.role` закрыт от self-update, unsafe RPC переведены на session-bound поведение.
- [FIX] Все пять Supabase `security_definer_view` ERROR закрыты через `security_invoker=true`.
- [ADD] Добавлены backend-контракты onboarding/legal consent/account deletion/admin chat/announcements и соответствующие Flutter gates.
- [ADD] Добавлены локальные legal artifacts: privacy policy, terms, account deletion text и Google OAuth setup checklist.
- [NOTE] Google Cloud/Supabase provider smoke и hosted public deletion URL остаются внешними release blockers.
