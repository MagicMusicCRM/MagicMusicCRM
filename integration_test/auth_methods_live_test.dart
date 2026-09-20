import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/security/password_policy.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/auth_methods_screen.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final role in ['admin', 'manager', 'director', 'teacher', 'client']) {
    testWidgets(
      '$role authentication method controls',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'auth-methods');
        await h.initialize(size: const Size(1440, 1600));
        final account = (h.fixture['accounts'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((a) => a['role'] == role);
        final password = '${h.fixture['password']}-changed';
        Finder field(String label) => find.widgetWithText(TextFormField, label);
        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(AuthMethodsScreen(key: UniqueKey()));
          await h.waitFor(
            () => find.byType(SwitchListTile).evaluate().isNotEmpty,
            'Authentication methods loaded',
          );
          await h.quiet();
        }

        Future<void> edit(String label, String text) async {
          await h.tap(field(label));
          await tester.enterText(field(label), text);
          await tester.pump();
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: field(label),
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
            text,
          );
        }

        int writes() => h.requests.where((r) => r['method'] != 'GET').length;
        await h.check(
          'OPEN',
          'Способы входа показывают почту, пароль и выключенный код из письма',
          () async {
            await open();
            expect(find.text(account['email'] as String), findsOneWidget);
            expect(
              find.text('Можно входить по почте и паролю'),
              findsOneWidget,
            );
            expect(
              tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
              isFalse,
            );
          },
        );
        await h.check(
          'EMAIL-VALIDATION',
          'Пустая, некорректная и прежняя почта отклоняются без HTTP-записи',
          () async {
            final before = writes();
            await h.tap(find.text('Изменить почту и выйти'));
            expect(find.text('Укажите новую почту'), findsOneWidget);
            expect(find.text('Введите текущий пароль'), findsOneWidget);
            await edit('Новая почта', 'invalid');
            await h.tap(find.text('Изменить почту и выйти'));
            expect(find.text('Некорректный адрес почты'), findsOneWidget);
            await edit(
              'Новая почта',
              (account['email'] as String).toUpperCase(),
            );
            await h.tap(find.text('Изменить почту и выйти'));
            expect(
              find.text('Новая почта совпадает с текущей'),
              findsOneWidget,
            );
            expect(writes(), before);
          },
        );
        await h.check(
          'PASSWORD-VALIDATION',
          'Короткий пароль и несовпадающее подтверждение отклоняются',
          () async {
            await open();
            final before = writes();
            await edit('Новый пароль', 'short');
            await edit('Повторите пароль', 'short');
            await h.tap(find.text('Сохранить пароль'));
            expect(find.text(passwordMinimumHint), findsOneWidget);
            await edit('Новый пароль', password);
            await edit('Повторите пароль', '$password-mismatch');
            await h.tap(find.text('Сохранить пароль'));
            expect(find.text('Пароли не совпадают'), findsOneWidget);
            expect(writes(), before);
          },
        );
        await h.check(
          'PASSWORD-REVEAL',
          'Показать и скрыть оба поля пароля',
          () async {
            await h.tap(find.byTooltip('Показать пароль'));
            for (final label in ['Новый пароль', 'Повторите пароль']) {
              expect(
                tester
                    .widget<EditableText>(
                      find.descendant(
                        of: field(label),
                        matching: find.byType(EditableText),
                      ),
                    )
                    .obscureText,
                isFalse,
              );
            }
            await h.tap(find.byTooltip('Скрыть пароль'));
            for (final label in ['Новый пароль', 'Повторите пароль']) {
              expect(
                tester
                    .widget<EditableText>(
                      find.descendant(
                        of: field(label),
                        matching: find.byType(EditableText),
                      ),
                    )
                    .obscureText,
                isTrue,
              );
            }
          },
        );
        for (final enabled in [true, false]) {
          await h.check(
            enabled ? 'MFA-ENABLE' : 'MFA-DISABLE',
            '${enabled ? 'Включить' : 'Выключить'} код из письма, проверить API и повторное открытие',
            () async {
              await open();
              final before = writes();
              await h.tap(find.byType(SwitchListTile));
              await h.quiet();
              expect(writes(), before + 1);
              final profile = await h.api.get<Map<String, dynamic>>(
                '/profile/me',
              );
              h.facts.add({
                'step': h.currentStep,
                'enabled': profile['emailOtp2faEnabled'],
              });
              expect(profile['emailOtp2faEnabled'], enabled);
              await open();
              expect(
                tester
                    .widget<SwitchListTile>(find.byType(SwitchListTile))
                    .value,
                enabled,
              );
            },
          );
        }
        await h.check(
          'PASSWORD-SAVE',
          'Сохранить новый пароль; проверить результат и состояние формы',
          () async {
            await open();
            await edit('Новый пароль', password);
            await edit('Повторите пароль', password);
            await h.tap(find.text('Сохранить пароль'));
            await h.quiet();
            expect(
              find.text('Пароль для входа по почте сохранен'),
              findsOneWidget,
            );
            expect(
              find.text('Не удалось загрузить способы входа.'),
              findsNothing,
            );
            for (final label in ['Новый пароль', 'Повторите пароль']) {
              expect(
                tester
                    .widget<EditableText>(
                      find.descendant(
                        of: field(label),
                        matching: find.byType(EditableText),
                      ),
                    )
                    .controller
                    .text,
                '',
              );
            }
          },
        );
        await h.check(
          'LOGIN-NEW-PASSWORD',
          'Новый пароль позволяет получить новую сессию через реальный API',
          () async {
            final response = await h.api.post<Map<String, dynamic>>(
              '/auth/login',
              authenticated: false,
              data: {'email': account['email'], 'password': password},
            );
            expect(response['session'], isA<Map>());
            expect((response['user'] as Map)['role'], role);
            h.facts.add({
              'step': h.currentStep,
              'newSessionIssued': response['session'] is Map,
              'role': (response['user'] as Map)['role'],
            });
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }
}
