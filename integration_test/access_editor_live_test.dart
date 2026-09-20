import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/security/access_management.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/access_editor_sheet.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['manager', 'director']) {
    testWidgets(
      '$role actual role and capability editor',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'access-editor');
        await h.initialize(size: const Size(1440, 1250));
        final target = h.fixture['accessTargetId'] as String,
            service = h.scope.read(accessManagementServiceProvider);
        const capability = 'crm.client.read.basic';
        Finder key(String value) => find.byKey(ValueKey(value));
        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            Scaffold(
              body: AccessEditorSheet(
                actorRole: role,
                userId: target,
                userLabel: 'Синтетический администратор',
                embedded: true,
              ),
            ),
          );
          await h.quiet();
        }

        Future<ManagedUserAccess> read() async {
          final r = await service.getUserAccess(target);
          h.facts.add({
            'step': h.currentStep,
            'role': r.role,
            'accessVersion': r.accessVersion,
            'capabilities': r.capabilities
                .map(
                  (c) => {
                    'key': c.key,
                    'allowed': c.effectiveAllowed,
                    'override': c.overrideEffect,
                  },
                )
                .toList(),
          });
          return r;
        }

        Future<void> choose(String label) async {
          await h.tap(key('access-role-selector'));
          await h.tap(find.text(label).last);
          await h.quiet();
        }

        if (role == 'manager') {
          await h.check(
            'FORBIDDEN',
            'Управляющий не получает редактор прав и не запускает запросы к нему',
            () async {
              final start = h.requests.length;
              await open();
              expect(key('access-editor-forbidden'), findsOneWidget);
              expect(
                h.requests
                    .skip(start)
                    .where(
                      (r) => (r['path'] as String).startsWith(
                        '/api/access/users/',
                      ),
                    ),
                isEmpty,
              );
            },
          );
          await h.finish();
          return;
        }
        await h.check(
          'OPEN',
          'Директор открывает актуальную роль и персональные права администратора',
          () async {
            await open();
            expect((await read()).role, 'admin');
            expect(key('access-capability-$capability'), findsOneWidget);
          },
        );
        await h.check(
          'ROLE-LIMIT',
          'Выбор роли исключает директора и администратора системы',
          () async {
            final w = tester.widget<DropdownButton<String>>(
              find.descendant(
                of: key('access-role-selector'),
                matching: find.byType(DropdownButton<String>),
              ),
            );
            expect(w.items!.map((i) => i.value), isNot(contains('director')));
            expect(
              w.items!.map((i) => i.value),
              isNot(contains('system_admin')),
            );
          },
        );
        await h.check(
          'DENY',
          'Отключить персональное право чтения клиентов',
          () async {
            await h.tap(key('access-capability-$capability'));
            await h.quiet();
            final c = (await read()).capabilities.singleWhere(
              (c) => c.key == capability,
            );
            expect(c.effectiveAllowed, false);
            expect(c.overrideEffect, 'deny');
          },
        );
        await h.check(
          'DENY-REOPEN',
          'Повторное открытие сохраняет запрет права',
          () async {
            await open();
            expect(
              tester
                  .widget<SwitchListTile>(key('access-capability-$capability'))
                  .value,
              false,
            );
          },
        );
        await h.check(
          'CONFIRMATION',
          'Смена роли требует отдельного подтверждения сброса персональных прав',
          () async {
            await choose('Управляющий');
            expect(key('access-role-reset-warning'), findsOneWidget);
            final start = h.requests.length;
            await h.tap(key('access-save-role'));
            await h.quiet();
            expect(
              find.text('Подтвердите сброс персональных настроек доступа.'),
              findsOneWidget,
            );
            expect(
              h.requests.skip(start).where((r) => r['method'] != 'GET'),
              isEmpty,
            );
            expect((await read()).role, 'admin');
          },
        );
        await h.check(
          'CANCEL',
          'Закрытие без сохранения сохраняет прежнюю роль и запрет',
          () async {
            await open();
            final r = await read();
            expect(r.role, 'admin');
            expect(
              r.capabilities
                  .singleWhere((c) => c.key == capability)
                  .overrideEffect,
              'deny',
            );
          },
        );
        await h.check(
          'ROLE-SAVE',
          'Подтвердить смену роли на управляющего со сбросом override',
          () async {
            await choose('Управляющий');
            await h.tap(key('access-reset-confirmation'));
            await h.tap(key('access-save-role'));
            await h.quiet();
            final r = await read();
            expect(r.role, 'manager');
            expect(r.capabilities.every((c) => c.overrideEffect == null), true);
          },
        );
        await h.check(
          'ROLE-REOPEN',
          'Повторное открытие показывает сохранённую роль управляющего',
          () async {
            await open();
            expect(
              tester
                  .widget<DropdownButtonFormField<String>>(
                    key('access-role-selector'),
                  )
                  .initialValue,
              'manager',
            );
            expect((await read()).role, 'manager');
          },
        );
        await h.check(
          'RESTORE',
          'Вернуть исходную роль администратора через тот же редактор',
          () async {
            await choose('Администратор');
            await h.tap(key('access-reset-confirmation'));
            await h.tap(key('access-save-role'));
            await h.quiet();
            expect((await read()).role, 'admin');
          },
        );
        await h.check(
          'FINAL',
          'Исходная роль восстановлена; изменения отражены новыми версиями доступа',
          () async {
            await open();
            final r = await read();
            expect(r.role, 'admin');
            expect(r.accessVersion, greaterThan(1));
            expect(
              r.capabilities
                  .singleWhere((c) => c.key == capability)
                  .effectiveAllowed,
              true,
            );
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );
  }
}
