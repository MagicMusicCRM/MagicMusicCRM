import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/router/app_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/account_deletion_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/account_deletion_status_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';

import 'evidence_screenshot.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director', 'teacher', 'client']) {
    testWidgets(
      '$role own account deletion request and withdrawal',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'deletion');
        await h.initialize(size: const Size(1440, 1100));
        final profile = await h.api.patch<Map<String, dynamic>>(
          '/profile/me',
          data: {
            'firstName': 'Запрос',
            'lastName': 'Удаление',
            'phone':
                '+79992220${['admin', 'manager', 'director', 'teacher', 'client'].indexOf(role) + 101}',
          },
        );
        final docs = await h.api.get<List<dynamic>>('/legal/documents/current');
        await h.api.post<Map<String, dynamic>>(
          '/legal/consents/current',
          data: {'documentIds': docs.map((d) => (d as Map)['id']).toList()},
        );
        h.facts.add({
          'step': 'setup',
          'profileId': profile['id'],
          'userId': profile['userId'],
        });
        GoRouter router() => h.scope.read(routerProvider);
        final routers = <GoRouter>{};
        addTearDown(() {
          for (final r in routers) {
            r.dispose();
          }
        });
        final roleRoute = switch (role) {
          'manager' || 'director' => '/manager',
          _ => '/$role',
        };
        Future<Map<String, dynamic>> request() async {
          final row = await h.api.get<Map<String, dynamic>>(
            '/profile/deletion-request',
          );
          h.facts.add({'step': h.currentStep, 'request': row});
          return row;
        }

        await h.check(
          'OPEN',
          'Маршрутизатор → профиль → форма запроса удаления',
          () async {
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: h.scope,
                child: RepaintBoundary(
                  key: evidenceRootKey,
                  child: Consumer(
                    builder: (context, ref, child) {
                      final activeRouter = ref.watch(routerProvider);
                      routers.add(activeRouter);
                      return MaterialApp.router(
                        theme: AppTheme.production,
                        routerConfig: activeRouter,
                        localizationsDelegates: const [
                          GlobalMaterialLocalizations.delegate,
                          GlobalWidgetsLocalizations.delegate,
                          GlobalCupertinoLocalizations.delegate,
                        ],
                        supportedLocales: const [Locale('ru'), Locale('en')],
                        locale: const Locale('ru'),
                      );
                    },
                  ),
                ),
              ),
            );
            await h.waitFor(
              () =>
                  router().routeInformationProvider.value.uri.path == roleRoute,
              'Authenticated role route ready',
            );
            router().go('/profile');
            await h.waitFor(
              () =>
                  find.byType(ProfileScreen).evaluate().isNotEmpty &&
                  find.text('Удалить аккаунт').evaluate().isNotEmpty,
              'Profile loaded',
            );
            await h.tap(find.text('Удалить аккаунт'));
            await h.waitFor(
              () => find.byType(AccountDeletionScreen).evaluate().isNotEmpty,
              'Deletion request form opened',
            );
          },
        );
        await h.check(
          'CONFIRMATION',
          'Без подтверждения отправка запрещена; снятие флажка снова блокирует кнопку',
          () async {
            final button = find.widgetWithText(
              FilledButton,
              'Отправить запрос',
            );
            expect(tester.widget<FilledButton>(button).onPressed, isNull);
            await h.tap(find.byType(CheckboxListTile));
            expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
            await h.tap(find.byType(CheckboxListTile));
            expect(tester.widget<FilledButton>(button).onPressed, isNull);
          },
        );
        String? requestId;
        await h.check(
          'REQUEST',
          'Отправить подтверждённый запрос с причиной; API и экран показывают pending',
          () async {
            final field = find.widgetWithText(TextField, 'Причина обращения');
            await h.tap(field);
            await tester.enterText(field, 'DELETION-$role');
            await h.tap(find.byType(CheckboxListTile));
            await h.tap(find.text('Отправить запрос'));
            await h.waitFor(
              () => find
                  .byType(AccountDeletionStatusScreen)
                  .evaluate()
                  .isNotEmpty,
              'Pending deletion route rendered',
            );
            await h.waitFor(
              () => find.text('Запрос принят').evaluate().isNotEmpty,
              'Pending state loaded',
            );
            final row = await request();
            requestId = row['id'] as String;
            expect(row['status'], 'pending');
            expect(row['reason'], 'DELETION-$role');
            expect(
              (await h.api.get<Map<String, dynamic>>(
                '/legal/gate',
              ))['deletionPending'],
              isTrue,
            );
          },
        );
        if (requestId == null) {
          for (final step in [
            'PENDING-GATE',
            'CANCEL-KEEP',
            'CANCEL-COMMIT',
            'RESTORED',
          ]) {
            h.blocked(
              step,
              'Продолжение запроса удаления',
              'No confirmed request ID',
            );
          }
        } else {
          await h.check(
            'PENDING-GATE',
            'Активный запрос удерживает пользователя на экране статуса',
            () async {
              final before = h.requests.length;
              router().go('/profile');
              await h.quiet();
              expect(find.byType(AccountDeletionStatusScreen), findsOneWidget);
              expect(find.byType(ProfileScreen), findsNothing);
              expect(
                h.requests
                    .skip(before)
                    .where((r) => r['path'] == '/api/profile/me'),
                isEmpty,
              );
              expect((await request())['id'], requestId);
            },
          );
          await h.check(
            'CANCEL-KEEP',
            'Отказ от отзыва сохраняет запрос без DELETE',
            () async {
              final before = h.requests
                  .where((r) => r['method'] == 'DELETE')
                  .length;
              await h.tap(
                find.byKey(const ValueKey('cancel-deletion-request')),
              );
              await h.tap(find.text('Оставить запрос'));
              expect((await request())['status'], 'pending');
              expect(
                h.requests.where((r) => r['method'] == 'DELETE').length,
                before,
              );
            },
          );
          await h.check(
            'CANCEL-COMMIT',
            'Подтвердить отзыв; запрос отменяется, рабочее пространство возвращается',
            () async {
              await h.tap(
                find.byKey(const ValueKey('cancel-deletion-request')),
              );
              await h.tap(
                find.byKey(const ValueKey('confirm-cancel-deletion-request')),
              );
              await h.waitFor(
                () =>
                    router().routeInformationProvider.value.uri.path ==
                    roleRoute,
                'Workspace access restored',
              );
              final row = await request();
              expect(row['id'], requestId);
              expect(row['status'], 'cancelled');
              expect(
                (await h.api.get<Map<String, dynamic>>(
                  '/legal/gate',
                ))['deletionPending'],
                isFalse,
              );
            },
          );
          await h.check(
            'RESTORED',
            'Профиль снова открывается; аккаунт и история запроса сохранены',
            () async {
              router().go('/profile');
              await h.waitFor(
                () =>
                    find.byType(ProfileScreen).evaluate().isNotEmpty &&
                    find.text('Способы входа').evaluate().isNotEmpty,
                'Profile usable after request withdrawal',
              );
              expect(
                (await h.api.get<Map<String, dynamic>>('/profile/me'))['id'],
                profile['id'],
              );
              expect((await request())['status'], 'cancelled');
            },
          );
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
