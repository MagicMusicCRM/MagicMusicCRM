# 02_ARCHITECTURE — MagicMusic CRM

**Status**: Baseline (Updated from v1.0.17)
**Last Verified**: 2026-04-15
**Source**: 58 Dart files + SQL migrations analysis (April Updates)

## 1. High-Level Technology Stack
- **Frontend**: Flutter ^3.11.1 (Multi-target: Windows/Android/iOS)
- **Backend / DB / Auth**: Supabase ^2.12.0 (PostgreSQL with optimized indexes)
- **State Management**: Riverpod ^3.3.1
- **Real-time Engine**: Supabase Realtime & Presence (Typing indicators, active admin tracking, message status).
- **Push Notifications**: Firebase Messaging ^15.2.0
- **Admin Tools**: Встроенная система Presence для координации администраторов в чатах.
- **Deep Linking**: `magiccrm://` protocol for auto-login and verification.
- **Routing**: go_router ^17.1.0
- **Build System**: Scripts for Windows Setup generation and GitHub-based updates.

## 2. Expanded Directory Structure
- `lib/core/`:
  - `providers/`: Global state management for Chat, Real-time, and Theme.
  - `services/`: HolliHop sync, Chat attachments, Notifications, Update checking.
  - `router/`, `theme/`, `widgets/`, `constants/`.
- `lib/features/`: Functional modules by role.
  - `admin/`, `auth/`, `client/`, `manager/`, `teacher/`.

## 3. Database Schema (v3)
Core tables and relationships:
- **Entities**: `students`, `teachers`, `groups`, `leads`.
- **Relationships**: `group_students` (many-to-many students/groups).
- **Operations**: `lessons` (schedule), `tasks` (manager assignments), `entity_comments`.
- **Communication**: `messages` (updated with `forwarded_from_id` and `pinned_at`), `group_chats` (metadata: `first_responder_id`, `responded_at`).
- **Internal Collaboration**: `profile_notes` (для заметок администраторов/менеджеров о клиентах).
- **Integrations**: `hollihop_id` fields for external system mapping.

## 4. Current Architectural Goals
- **Service Isolation**: Move remaining DB logic from Widgets to `Supa-` services.
- **Provider Consistency**: Standardize usage of `realtime_providers.dart` for all live updates.
- **Presence Utilization**: Расширение использования Presence для отображения активности сотрудников во всей CRM.
- **Security Protocols**: Усиление политик RLS для защиты чувствительной информации во внутренних таблицах.
