# Ponytail Audit Report - Over-Engineering

**Date**: 2026-06-16  
**Scope**: Flutter frontend (`lib/`, `test/`, `integration_test/`), NestJS backend (`server/src`, `server/db`), scripts, tracked repository artifacts.  
**Mode**: `ponytail-audit` - complexity only. This report does not cover correctness, security, or performance bugs unless they are caused by excess structure.

## Summary

The app is not failing because of missing architecture. The largest cost is old architecture kept alive after the v3 cutover: legacy Supabase scripts, disabled Google OAuth backend, source-text tests, legacy DTO adapters, and tracked generated artifacts.

**Fastest safe cuts**:

1. Remove tracked archives/generated captures from Git.
2. Delete disabled backend Google OAuth implementation while keeping `410 Gone` compatibility routes.
3. Delete the unused `ScopedRepository`.
4. Replace `test/widget_test.dart` source-grep checks with a few runnable behavior/config checks.
5. Remove unused direct Flutter dependencies.

## Cleanup Applied

Applied on 2026-06-16:

- Done: findings 1-6 and 8-12.
- Deferred: finding 7. CRM DTO shape is a screen-by-screen migration and should not be mixed with cleanup-only changes.

## Metrics

| Area | Files | Lines |
|---|---:|---:|
| Flutter app `lib` | 106 | 37,484 |
| Backend `server/src` | 182 | 26,521 |
| DB migrations | 40 | 1,219 |
| Scripts | 5 | 638 |
| Flutter tests | 14 | 5,861 |
| Integration tests | 1 | 214 |

Tracked non-source bulk:

| Path | Files | Size |
|---|---:|---:|
| `_archive/` | 293 | 185.05 MB |
| `installer_output/` | 1 | 11.87 MB |
| root Android bugreport zip | 1 | 5.43 MB |
| `ast_nodes*.json` | 2 | 0.42 MB |

## Ranked Findings

1. `delete:` tracked generated archives and captures. Replace with ignored local evidence storage or release artifacts, not Git. [`_archive/`, `installer_output/`, `bugreport-sdk_gphone64_x86_64-BE4B.251210.005-2026-04-14-10-09-59.zip`, `ast_nodes.json`, `ast_nodes_v2.json`]

2. `delete:` disabled Google OAuth backend is still registered and tested, while controller routes return `GoneException`. Keep the four `410 Gone` routes; delete `GoogleOAuthService`, provider, DTOs, tests, module exports and env wiring until product re-enables Google login. Keep `google-auth-library`: Firebase push notifications use it. [`server/src/auth/auth.controller.ts:80`, `server/src/auth/auth.module.ts:9`, `server/src/auth/google-oauth.service.ts`, `server/src/auth/google-oauth.provider.ts`, `server/src/auth/dto/google-oauth-*.ts`, `server/src/auth/google-oauth.service.spec.ts`, `server/src/notifications/notification-push.provider.ts`]

3. `delete:` `ScopedRepository` is an abstract repository with zero production implementations; only its own test extends it. Replace with nothing. [`server/src/db/scoped-repository.ts`, `server/src/db/scoped-repository.spec.ts`]

4. `delete:` legacy Supabase one-off scripts still sit next to active scripts and write directly to Supabase REST. Replace with v3 migrations/importers or move to ignored archive. [`scripts/fix_db_data.py`, `scripts/insert_missing_data.py`, `fix_groups.sql`, `fix_groups_robust.sql`, `supabase_migration_avatar_url.sql`]

5. `delete:` `generate_doc.py` generates an obsolete Supabase custom-domain DOCX to an old local path. Replace with the existing Markdown doc or delete both generator and generated DOCX if no longer needed. [`generate_doc.py`, `docs/Supabase_Custom_Domain_Setup_Guide.docx`, `docs/supabase_custom_domain_setup_guide.md`]

6. `shrink:` `test/widget_test.dart` is 1,103 lines of source-text assertions (`contains`, `isNot(contains)`, `indexOf`) that lock implementation shape instead of behavior. Replace with 3-5 real checks: package metadata, no Supabase runtime dependency, integration smoke wiring, and maybe Android launch theme. [`test/widget_test.dart:6`]

7. `shrink:` Flutter CRM client maps the v3 API back into legacy Supabase-shaped maps through ~600+ lines of `_legacy*` adapters. Replace with v3 DTO names in widgets as files are touched; do not add a second model layer. [`lib/core/services/magic_crm_service.dart:1273`]

8. `delete:` `chat_providers.dart` keeps old REST-as-`StreamProvider` providers that are not used by the app; only `messengerNavigationProvider` is referenced. Move that notifier to a tiny navigation file and delete the dead chat/message/channel providers. [`lib/core/providers/chat_providers.dart:11`, `lib/features/messenger/presentation/screens/messenger_screen.dart:147`]

9. `stdlib/native:` remove unused direct Flutter dependencies. No imports were found for `google_fonts`, `cupertino_icons`, `package_info_plus`, `uuid`, or `cross_file`. Let transitive deps stay transitive. [`pubspec.yaml:38`, `pubspec.yaml:42`, `pubspec.yaml:47`, `pubspec.yaml:61`, `pubspec.yaml:65`]

10. `shrink:` `MagicCrmReferenceCache` is a hand-rolled TTL/stale-while-refresh cache over small reference lists. Riverpod already caches provider results; use simple providers plus explicit invalidation after writes. [`lib/core/services/magic_crm_reference_cache.dart:14`]

11. `yagni:` `MagicSettingsService` and `ChatAttachmentService` each create their own static `MagicApiClient` plus debug override outside the existing Riverpod provider path. Keep the file helpers, but move API calls behind normal providers when touched. [`lib/core/services/magic_settings_service.dart:73`, `lib/core/services/chat_attachment_service.dart:16`]

12. `shrink:` `AdminOverviewWidget` polls stats every 10 seconds with a `StreamProvider` for four dashboard counters. Replace with `FutureProvider` and manual refresh unless real-time dashboard updates are a product requirement. [`lib/features/admin/presentation/widgets/admin_overview_widget.dart:6`]

## Keep

Do not cut these just because they look large:

- `server/src/migration/hollihop-import.ts`: active S7 blocker depends on live DB-backed dry-run.
- `server/src/security/security-gate.ts`: launch gate, not feature bloat.
- `socket_io_client` / Socket.IO backend packages: current messenger realtime path.
- `syncfusion_flutter_calendar`: one import, but replacing `SfCalendar` with hand-made calendar UI would likely add code.
- `flutter_local_notifications`, `local_notifier`, `firebase_messaging`: separate mobile/desktop/push concerns, not duplicate by itself.
- `MagicTokenStore` abstraction: two real implementations (`SecureMagicTokenStore`, `MemoryMagicTokenStore`) and test/integration use.

## Cut Plan

1. **Repo hygiene cut**: remove tracked archives/generated captures and add ignore rules for `_archive/`, `installer_output/`, root bugreport zips, and `ast_nodes*.json`.
2. **Dead backend cut**: remove disabled Google OAuth implementation and unused `ScopedRepository`.
3. **Legacy script cut**: delete/move one-off Supabase scripts and stale DOCX generator.
4. **Test shrink**: replace source-grep `widget_test.dart` with small behavior/config checks.
5. **Flutter dependency cut**: remove unused direct deps and run `flutter pub get`, `flutter analyze`, `flutter test`.
6. **Touch-only cleanup**: retire legacy CRM mappers, manual caches, and static API clients while editing affected screens.

## Net

Immediate safe target: **~2,000 lines removed, 5 direct Flutter deps removed, ~202 MB tracked artifacts removed**.

Larger touch-only target after CRM/widget migration: **~2,600-3,000 lines removed** without changing product scope.
