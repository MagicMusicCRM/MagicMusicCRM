import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_bubble.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_dialog.dart';
import 'package:magic_music_crm/features/client/presentation/screens/client_dashboard_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['client', 'teacher', 'admin', 'manager', 'director']) {
    testWidgets(
      '$role reactions forwards pins and chat mute',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'messenger-extras');
        await h.initialize(size: const Size(1440, 1100));
        final service = h.scope.read(magicMessengerServiceProvider),
            chatId = h.fixture['chatId'] as String,
            forwardId = h.fixture['forwardId'] as String;
        final text = 'AUDIT-EXTRAS-$role';
        final seeded = await service.sendMessage(chatId, content: text);
        final messageId = seeded['id'] as String;
        Finder bubble() => find.byWidgetPredicate(
          (w) => w is MessageBubble && w.message['id'] == messageId,
        );
        Future<Map<String, dynamic>> current() async {
          final row = (await service.listMessages(
            chatId,
          )).singleWhere((m) => m['id'] == messageId);
          h.facts.add({'step': h.currentStep, 'message': row});
          return row;
        }

        Future<List<Map<String, dynamic>>> forwards() async =>
            (await service.listMessages(
              forwardId,
            )).where((m) => m['forwarded_from_id'] == messageId).toList();
        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            role == 'client'
                ? const ClientDashboardScreen()
                : const StaffWorkspaceScreen(),
          );
          await h.waitFor(
            () => find.text('AUDIT-EXTRA-CHAT').evaluate().isNotEmpty,
            'Chat list loaded',
          );
          await h.tap(find.text('AUDIT-EXTRA-CHAT').first);
          await h.quiet();
        }

        Future<void> contextMenu() async {
          final target = find
              .descendant(
                of: bubble(),
                matching: find.byWidgetPredicate(
                  (w) => w is GestureDetector && w.onSecondaryTap != null,
                ),
              )
              .first;
          await tester.ensureVisible(target);
          await tester.tap(target, buttons: kSecondaryMouseButton);
          await h.quiet();
        }

        Future<void> menu(String label) async {
          await contextMenu();
          await h.tap(find.widgetWithText(ListTile, label));
          await h.quiet();
        }

        Future<void> info() async {
          await h.tap(find.text('AUDIT-EXTRA-CHAT').last);
          await h.quiet();
          expect(find.byType(ChatInfoDialog), findsOneWidget);
        }

        Future<bool> muted() async {
          final row = await service.getChat(chatId);
          h.facts.add({'step': h.currentStep, 'chat': row});
          return row['is_muted'] == true;
        }

        await h.check(
          'OPEN',
          'Открыть чат с сохранённым текстом для дополнительных действий',
          () async {
            await open();
            expect(bubble(), findsOneWidget);
          },
        );
        await h.check(
          'REACTION-ADD',
          'Добавить реакцию из меню и проверить запись',
          () async {
            await contextMenu();
            await h.tap(find.byTooltip('Реакция 👍'));
            await h.quiet();
            final reactions = (await current())['reactions'] as List;
            expect(
              reactions.singleWhere((r) => r['emoji'] == '👍')['count'],
              1,
            );
          },
        );
        await h.check(
          'REACTION-REOPEN',
          'Повторное открытие показывает свою реакцию',
          () async {
            await open();
            final reactions = (await current())['reactions'] as List;
            expect(
              reactions.singleWhere((r) => r['emoji'] == '👍')['reactedByMe'],
              true,
            );
          },
        );
        await h.check(
          'REACTION-REMOVE',
          'Повторное нажатие реакции удаляет её',
          () async {
            await contextMenu();
            await h.tap(find.byTooltip('Реакция 👍'));
            await h.quiet();
            expect((await current())['reactions'], isEmpty);
          },
        );
        await h.check(
          'FORWARD-CANCEL',
          'Отмена пересылки после выбора чата не создаёт сообщение',
          () async {
            await open();
            await menu('Переслать');
            await h.tap(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.text('AUDIT-FORWARD-CHAT'),
              ),
            );
            await h.tap(find.widgetWithText(TextButton, 'Отмена'));
            expect(await forwards(), isEmpty);
          },
        );
        await h.check(
          'FORWARD',
          'Подтверждённая пересылка сохраняет текст и исходный ID в другом чате',
          () async {
            await menu('Переслать');
            await h.tap(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.text('AUDIT-FORWARD-CHAT'),
              ),
            );
            await h.tap(find.widgetWithText(ElevatedButton, 'Переслать'));
            await h.quiet();
            final rows = await forwards();
            expect(rows.length, 1);
            expect(rows.single['content'], text);
            h.facts.add({'step': h.currentStep, 'forward': rows.single});
          },
        );
        if (!['client', 'teacher'].contains(role)) {
          await h.check(
            'PIN',
            'Доступная в меню команда закрепления должна сохраняться',
            () async {
              await open();
              await menu('Закрепить');
              expect((await current())['pinned_at'], isNotNull);
            },
          );
          await h.check(
            'PIN-REOPEN',
            'Закрепление сохраняется после повторного открытия',
            () async {
              await open();
              expect((await current())['pinned_at'], isNotNull);
              expect(find.text('Закрепленное сообщение'), findsWidgets);
            },
          );
          await h.check(
            'UNPIN',
            'Открепить сообщение и проверить отсутствие отметки',
            () async {
              await menu('Открепить');
              expect((await current())['pinned_at'], isNull);
            },
          );
        } else {
          await h.check(
            'PIN-HIDDEN',
            'Участник без права управления группой не видит закрепление',
            () async {
              await open();
              await contextMenu();
              expect(
                find.widgetWithText(ListTile, 'Закрепить').hitTestable(),
                findsNothing,
              );
              await tester.tapAt(const Offset(12, 12));
              await tester.pump();
            },
          );
        }
        await h.check(
          'MUTE',
          'Заглушить чат через сведения и сохранить настройку',
          () async {
            await open();
            await info();
            await h.tap(find.text('Заглушить'));
            await h.quiet();
            expect(await muted(), true);
          },
        );
        await h.check(
          'MUTE-REOPEN',
          'Повторное открытие сведений показывает заглушённый чат',
          () async {
            await open();
            await info();
            expect(find.text('Включить'), findsOneWidget);
            expect(await muted(), true);
          },
        );
        await h.check(
          'UNMUTE',
          'Включить оповещения чата и сохранить настройку',
          () async {
            await h.tap(find.text('Включить'));
            await h.quiet();
            expect(await muted(), false);
            await open();
            await info();
            expect(find.text('Заглушить'), findsOneWidget);
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 15)),
    );
  }
}
