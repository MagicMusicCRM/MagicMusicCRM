import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';
import 'package:magic_music_crm/core/widgets/notification_bell_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/clients_widget.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets(
      '$role notification inbox persists read markers',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'notifications-inbox');
        await h.initialize(size: const Size(1440, 1100));
        final service = h.scope.read(magicNotificationsServiceProvider),
            ids = (h.fixture['notificationIds'] as Map)[role] as List;
        final otherRole = role == 'director' ? 'admin' : 'director',
            foreignId =
                ((h.fixture['notificationIds'] as Map)[otherRole] as List).first
                    as String;
        Future<List<Map<String, dynamic>>> own() async {
          final rows = (await service.list())
              .where((r) => ids.contains(r['id']))
              .toList();
          h.facts.add({'step': h.currentStep, 'notifications': rows});
          return rows;
        }

        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(const Scaffold(body: ClientsWidget()));
          await h.quiet();
          await h.tap(find.byTooltip('Уведомления'));
          await h.quiet();
        }

        Finder badge(String text) => find.descendant(
          of: find.byType(NotificationBellWidget),
          matching: find.text(text),
        );
        await h.check(
          'OPEN',
          'Открыть два непрочитанных уведомления из раздела клиентов',
          () async {
            await open();
            final rows = await own();
            expect(rows.length, 2);
            expect(rows.every((r) => r['is_read'] == false), true);
            expect(find.text('AUDIT-INBOX-$role-1'), findsOneWidget);
            expect(find.text('AUDIT-INBOX-$role-2'), findsOneWidget);
            expect(badge('2'), findsOneWidget);
          },
        );
        await h.check(
          'READ-ONE',
          'Нажатие уведомления сохраняет прочтение и уменьшает счётчик',
          () async {
            await h.tap(find.text('AUDIT-INBOX-$role-1'));
            await h.quiet();
            final rows = await own();
            expect(rows.singleWhere((r) => r['id'] == ids[0])['is_read'], true);
            expect(
              rows.singleWhere((r) => r['id'] == ids[1])['is_read'],
              false,
            );
            expect(badge('1'), findsOneWidget);
          },
        );
        await h.check(
          'REOPEN',
          'Повторное открытие сохраняет один непрочитанный элемент',
          () async {
            await open();
            expect((await own()).where((r) => r['is_read'] == false).length, 1);
            expect(badge('1'), findsOneWidget);
          },
        );
        await h.check(
          'READ-ALL',
          'Прочитать все сохраняет отметки и убирает кнопку и счётчик',
          () async {
            await h.tap(find.text('Прочитать все'));
            await h.quiet();
            expect((await own()).every((r) => r['is_read'] == true), true);
            expect(find.text('Прочитать все'), findsNothing);
            expect(badge('1'), findsNothing);
            expect(badge('2'), findsNothing);
          },
        );
        await h.check(
          'FINAL',
          'После повторного открытия оба уведомления остаются прочитанными',
          () async {
            await open();
            expect((await own()).every((r) => r['is_read'] == true), true);
            expect(find.text('Прочитать все'), findsNothing);
          },
        );
        await h.check(
          'FOREIGN',
          'API не позволяет отметить уведомление другого получателя',
          () async {
            try {
              await service.markRead(foreignId);
              fail('Foreign notification accepted');
            } on MagicApiException catch (error) {
              expect(error.statusCode, 404);
            }
          },
          expectedHttpErrors: [
            (
              method: 'POST',
              path: '/api/notifications/$foreignId/read',
              status: 404,
              maxCount: 1,
            ),
          ],
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
