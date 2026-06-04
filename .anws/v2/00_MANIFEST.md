# .anws v2 — Список содержимого версии

**Дата создания**: 2026-05-30  
**Статус**: Active Design / Blueprint Ready  
**Предыдущая версия**: v1

## Цели версии

Сформировать архитектурный контракт для подготовки MagicMusicCRM к публикации в Google Play/App Store: безопасная регистрация через Google Account, обязательный onboarding с ФИО/телефоном, legal consent, удаление аккаунта, исправленная модель admin/global chat и hardening Supabase.

## Основные изменения

- Auth-first модель: Google OAuth/email login отделены от заполнения профиля.
- Безопасная модель ролей: клиент не может назначить себе `admin/manager/teacher` через metadata.
- Legal/compliance слой: Privacy Policy, Terms, consent versioning, account deletion.
- Новая модель коммуникаций: системный admin chat и глобальные уведомления без смешения direct/group/broadcast semantics.
- Supabase hardening: RLS, security-definer functions/views, storage policies, advisors.
- Release gates: analyzer/tests/security/store compliance before publication.

## Список документов

- [x] 00_MANIFEST.md (этот файл)
- [x] 01_PRD.md (Checkpoint 1 draft)
- [x] concept_model.json
- [x] 02_ARCHITECTURE_OVERVIEW.md
- [x] 03_ADR/
- [x] 04_SYSTEM_DESIGN/
- [x] 05_TASKS.md
- [x] 06_CHANGELOG.md
