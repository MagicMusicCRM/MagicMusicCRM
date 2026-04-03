# 01_PRD — MagicMusic CRM

**Status**: Baseline (Updated from v1.0.17)
**Version**: 1.0.17
**Owner**: Magic Music School

## 1. Vision & Purpose
MagicMusic CRM is a specialized management system for music schools. It centralizes scheduling, student tracking, invoicing, and teacher management into a single Flutter application with a Supabase backend.

## 2. Target Audience (Roles)
- **Admin**: Full system control, financial overview, managing entities.
- **Manager**: Sales, lead tracking, group management, invoicing, sales reports.
- **Teacher**: Schedule management, attendance tracking, student progress, real-time chat.
- **Client (Student/Parent)**: Viewing schedule, subscription status, homework, progress notes, real-time chat.

## 3. Core Features (Detailed v1.0.17)
- **Visual Excellence**: Premium dark theme with Glassmorphism and smooth micro-animations.
- **Cross-platform**: Native support for Windows (with sidebar) and mobile (Android/iOS).
- **Advanced Messenger (Telegram-style)**:
  - **Voice Messages**: Recording and playback support.
  - **File Handling**: Confirmation dialogs, attachment captions, Drag-and-drop.
  - **Media**: Built-in gallery and advanced image viewer.
- **Authentication & Onboarding**:
  - **Deep Linking**: Protocol `magiccrm://` for instant email verification on Windows.
  - **Auto-login**: Seamless entry after account verification.
  - **Enhanced Validation**: Domain-based validation for registration.
- **Real-time Collaboration**:
  - **Presence**: Real-time typing indicators ("Administrator is typing...", specific names for employees).
  - **Reactive UI**: Instant appearance of new users/clients in lists.
- **Notification & Updates**: Automated GitHub update system and reliable FCM notifications.
- **Windows Deployment**: Specialized scripts for building `Setup.exe` installers.

## 4. Key Fixes & Security
- **Role-based visibility**: Teachers' access restricted (cannot see Administration chat section).
- **UI Robustness**: SafeArea implementation to prevent system header overlap on Android.
- **Database**: Optimized SQL indexes for performance under load.
