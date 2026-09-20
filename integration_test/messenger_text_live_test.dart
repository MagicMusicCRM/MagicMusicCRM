import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_bubble.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_input.dart';
import 'package:magic_music_crm/features/client/presentation/screens/client_dashboard_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['client', 'teacher', 'admin', 'manager', 'director']) {
    testWidgets(
      '$role sends edits replies and deletes text through the real messenger',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'messenger-text');
        await h.initialize(size: const Size(1440, 1100));
        final service = h.scope.read(magicMessengerServiceProvider),
            chatId = h.fixture['chatId'] as String;
        final original = 'AUDIT-MESSAGE-$role',
            edited = 'AUDIT-EDITED-$role',
            reply = 'AUDIT-REPLY-$role';
        String? messageId;
        Finder input() => find.descendant(
          of: find.byType(MessageInput),
          matching: find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.hintText == 'Сообщение...',
          ),
        );
        Finder bubble() => find.byWidgetPredicate(
          (w) => w is MessageBubble && w.message['id'] == messageId,
        );
        Future<void> fill(String value) async {
          await h.tap(input());
          await tester.enterText(input(), value);
          await tester.pump();
        }

        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            role == 'client'
                ? const ClientDashboardScreen()
                : const StaffWorkspaceScreen(),
          );
          await h.waitFor(
            () => find.text('AUDIT-TEXT-CHAT').evaluate().isNotEmpty,
            'Shared synthetic chat loaded',
          );
          await h.tap(find.text('AUDIT-TEXT-CHAT').first);
          await h.quiet();
          expect(find.byType(MessageInput), findsOneWidget);
        }

        Future<Map<String, dynamic>> current() async {
          final row = (await service.listMessages(
            chatId,
          )).singleWhere((r) => r['id'] == messageId);
          h.facts.add({'step': h.currentStep, 'message': row});
          return row;
        }

        Future<void> menu(String action) async {
          final target = find
              .descendant(
                of: bubble(),
                matching: find.byWidgetPredicate(
                  (w) => w is GestureDetector && w.onLongPress != null,
                ),
              )
              .first;
          await tester.ensureVisible(target);
          final message = tester.widget<MessageBubble>(bubble());
          h.facts.add({
            'step': h.currentStep,
            'contextMenu': {
              'messageId': message.message['id'],
              'isMe': message.isMe,
              'deleted': message.message['deleted_at'] != null,
              'action': action,
              'gesture': 'secondary mouse button',
            },
          });
          await tester.tap(target, buttons: kSecondaryMouseButton);
          await h.quiet();
          await h.tap(find.widgetWithText(ListTile, action));
          await h.quiet();
        }

        await h.check(
          'OPEN',
          'Открыть существующий групповой чат из рабочего пространства',
          () async {
            await open();
            expect(
              (await service.listChats()).any((r) => r['id'] == chatId),
              true,
            );
          },
        );
        await h.check(
          'SEND',
          'Отправить текст и проверить единственную сохранённую запись',
          () async {
            await open();
            await fill(original);
            await h.tap(find.byTooltip('Отправить'));
            await h.quiet();
            final rows = (await service.listMessages(
              chatId,
            )).where((r) => r['content'] == original).toList();
            expect(rows.length, 1);
            messageId = rows.single['id'] as String;
            h.facts.add({'step': h.currentStep, 'message': rows.single});
            expect(bubble(), findsOneWidget);
            expect(tester.widget<TextField>(input()).controller!.text, '');
          },
        );
        if (messageId == null) {
          h.blocked(
            'MESSAGE-DEPENDENTS',
            'Правка, ответ и удаление',
            'Message send failed',
          );
          await h.finish();
          return;
        }
        await h.check(
          'REOPEN',
          'Повторное открытие показывает отправленное сообщение',
          () async {
            await open();
            expect(bubble(), findsOneWidget);
            expect((await current())['content'], original);
          },
        );
        await h.check(
          'EDIT-CANCEL',
          'Отмена редактирования оставляет исходный текст на сервере',
          () async {
            await menu('Изменить');
            expect(find.text('Редактирование'), findsOneWidget);
            await fill('CANCELLED-$role');
            await h.tap(find.byTooltip('Отменить'));
            await h.quiet();
            expect((await current())['content'], original);
          },
        );
        await h.check(
          'EDIT',
          'Правка сохраняет новый текст под прежним ID',
          () async {
            await open();
            await menu('Изменить');
            await fill(edited);
            await h.tap(find.byTooltip('Отправить'));
            await h.quiet();
            expect((await current())['content'], edited);
            await open();
            expect(
              tester.widget<MessageBubble>(bubble()).message['content'],
              edited,
            );
          },
        );
        await h.check(
          'REPLY',
          'Ответ сохраняется со ссылкой на исходное сообщение',
          () async {
            await menu('Ответить');
            expect(find.text('Ответ пользователю'), findsOneWidget);
            await fill(reply);
            await h.tap(find.byTooltip('Отправить'));
            await h.quiet();
            final row = (await service.listMessages(
              chatId,
            )).singleWhere((r) => r['content'] == reply);
            h.facts.add({'step': h.currentStep, 'message': row});
            expect(row['reply_to_id'], messageId);
          },
        );
        await h.check(
          'DELETE-CANCEL',
          'Отказ от удаления сохраняет сообщение',
          () async {
            await menu('Удалить');
            expect(find.text('Удаление сообщения'), findsOneWidget);
            await h.tap(find.widgetWithText(TextButton, 'Отмена'));
            expect((await current())['deleted_at'], isNull);
          },
        );
        await h.check(
          'DELETE',
          'Подтверждение удаления сохраняет отметку удаления',
          () async {
            await menu('Удалить');
            await h.tap(find.widgetWithText(TextButton, 'Удалить'));
            await h.quiet();
            expect((await current())['deleted_at'], isNotNull);
          },
        );
        await h.check(
          'DELETE-REOPEN',
          'После повторного открытия удаление сохранено, ответ остаётся',
          () async {
            await open();
            expect(
              tester.widget<MessageBubble>(bubble()).message['deleted_at'],
              isNotNull,
            );
            expect(
              (await service.listMessages(chatId))
                  .where(
                    (r) => r['content'] == reply && r['deleted_at'] == null,
                  )
                  .length,
              1,
            );
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );
  }
}
