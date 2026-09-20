import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/router/app_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/login_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/widgets/auth_form_controls.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/auth_methods_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';

import 'evidence_screenshot.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director', 'teacher', 'client']) {
    testWidgets(
      '$role change email, exit and sign in through production router',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'auth-email');
        await h.initialize(size: const Size(1440, 1600));
        final accounts = (h.fixture['accounts'] as List)
            .cast<Map<String, dynamic>>();
        final account = accounts.singleWhere((a) => a['role'] == role);
        final oldEmail = account['email'] as String;
        final newEmail = 'updated-$oldEmail';
        final profile = await h.api.patch<Map<String, dynamic>>(
          '/profile/me',
          data: {
            'firstName': 'Почта',
            'lastName': 'Маршрут',
            'phone': '+79991110${accounts.indexOf(account) + 101}',
          },
        );
        final docs = await h.api.get<List<dynamic>>('/legal/documents/current');
        await h.api.post<Map<String, dynamic>>(
          '/legal/consents/current',
          data: {'documentIds': docs.map((d) => (d as Map)['id']).toList()},
        );
        final gate = await h.api.get<Map<String, dynamic>>('/legal/gate');
        expect(gate['profileComplete'], isTrue);
        expect(gate['legalAccepted'], isTrue);
        h.facts.add({
          'step': 'setup',
          'profileId': profile['id'],
          'userId': profile['userId'],
          'gate': gate,
        });
        GoRouter currentRouter() => h.scope.read(routerProvider);
        final routers = <GoRouter>{};
        addTearDown(() {
          for (final router in routers) {
            router.dispose();
          }
        });
        final roleRoute = switch (role) {
          'manager' || 'director' => '/manager',
          _ => '/$role',
        };
        await h.check(
          'ROUTER-BOOT',
          'Настоящий маршрутизатор открывает рабочее пространство роли',
          () async {
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: h.scope,
                child: RepaintBoundary(
                  key: evidenceRootKey,
                  child: Consumer(
                    builder: (context, ref, child) {
                      final router = ref.watch(routerProvider);
                      routers.add(router);
                      return MaterialApp.router(
                        theme: AppTheme.production,
                        routerConfig: router,
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
                  currentRouter().routeInformationProvider.value.uri.path ==
                  roleRoute,
              'Authenticated role route ready',
            );
            await h.quiet();
          },
        );
        await h.check(
          'PROFILE-AUTH-ROUTE',
          'Маршрут профиля → кнопка «Способы входа»',
          () async {
            currentRouter().go('/profile');
            await h.waitFor(
              () => find.byType(ProfileScreen).evaluate().isNotEmpty,
              'Profile route rendered',
            );
            await h.waitFor(
              () => find.text('Способы входа').evaluate().isNotEmpty,
              'Profile loaded',
            );
            await h.tap(find.text('Способы входа'));
            await h.waitFor(
              () => find.byType(AuthMethodsScreen).evaluate().isNotEmpty,
              'Auth method route opened',
            );
            await h.waitFor(
              () => find
                  .widgetWithText(TextFormField, 'Новая почта')
                  .evaluate()
                  .isNotEmpty,
              'Auth fields loaded',
            );
            expect(find.byType(AuthMethodsScreen), findsOneWidget);
          },
        );
        await h.check(
          'CHANGE-EMAIL-EXIT',
          'Сменить почту, очистить сессию и перейти на настоящий экран входа',
          () async {
            for (final entry in {
              'Новая почта': newEmail,
              'Текущий пароль': h.fixture['password'] as String,
            }.entries) {
              final input = find.widgetWithText(TextFormField, entry.key);
              await h.tap(input);
              await tester.enterText(input, entry.value);
              await tester.pump();
            }
            await h.tap(find.text('Изменить почту и выйти'));
            await h.waitFor(
              () => find.byType(LoginScreen).evaluate().isNotEmpty,
              'Email change routed to login',
            );
            await h.quiet();
            expect(await h.api.readTokens(), isNull);
            expect(
              currentRouter().routeInformationProvider.value.uri.path,
              '/login',
            );
            h.facts.add({
              'step': h.currentStep,
              'signedOut': true,
              'route': '/login',
            });
          },
          expectedHttpErrors: const [
            (method: 'GET', path: '/api/legal/gate', status: 401, maxCount: 1),
          ],
        );
        await h.check(
          'LOGIN-NEW-EMAIL',
          'Войти новой почтой через форму; роль и профиль сохраняются',
          () async {
            for (final entry in {
              'Телефон или почта': newEmail,
              'Пароль': h.fixture['password'] as String,
            }.entries) {
              final wrapper = find.byWidgetPredicate(
                (w) => w is AuthField && w.label == entry.key,
              );
              final input = find.descendant(
                of: wrapper,
                matching: find.byType(TextFormField),
              );
              await h.tap(input);
              await tester.enterText(input, entry.value);
              await tester.pump();
            }
            await h.tap(find.text('Войти'));
            await h.waitFor(
              () =>
                  currentRouter().routeInformationProvider.value.uri.path ==
                  roleRoute,
              'New email login reached role workspace',
            );
            await h.quiet();
            final saved = await h.api.get<Map<String, dynamic>>('/profile/me');
            expect(saved['email'], newEmail);
            expect(saved['id'], profile['id']);
            expect(saved['role'], role);
            h.facts.add({
              'step': h.currentStep,
              'email': saved['email'],
              'profileId': saved['id'],
              'role': saved['role'],
              'route': roleRoute,
            });
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
