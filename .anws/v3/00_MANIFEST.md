# .anws v3 - Backend Independence

**Дата создания**: 2026-06-10
**Статус**: Active
**Предыдущая версия**: v2 (Publication Readiness)

## Цели версии

Перевести MagicMusicCRM с Supabase Cloud runtime на собственный backend в Москве: NestJS API, PostgreSQL, private file storage, WebSocket realtime, workers, backups, monitoring and security gates.

## Основные изменения

- Supabase перестает быть production runtime-зависимостью.
- Flutter переходит с прямого Supabase SDK на собственный HTTPS/WebSocket API.
- Авторизация, роли, файлы, realtime, legal/deletion and CRM-data access enforced by backend services.
- Production topology starts with one Moscow primary server plus external encrypted backups and tested restore.
- Security gates cover secrets, auth/session, authorization, data isolation, API security, infra, integrations and observability.

## Список документов

- [x] 00_MANIFEST.md
- [x] 01_PRD.md
- [x] 02_ARCHITECTURE_OVERVIEW.md
- [x] 03_ADR/
- [x] 04_SYSTEM_DESIGN/
- [x] 05_TASKS.md
- [x] 06_CHANGELOG.md
- [x] 07_CHALLENGE_REPORT.md
