import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_header.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_search_bar.dart';
import 'package:magic_music_crm/features/messenger/widgets/inbox_folder_bar.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director'])
    testWidgets('$role actual inbox and chat directory', (tester) async {
      final h = LiveAuditHarness(tester, role, 'messenger-inbox');
      await h.initialize(size: const Size(1600, 1200));
      final svc = h.scope.read(magicMessengerServiceProvider),
          inbox = h.fixture['inboxId'] as String;
      String memberName = 'Student0 HTTP test';
      String memberUser = h.fixture['clientUserId'],
          memberProfile = h.fixture['clientProfileId'];
      if (Platform.environment['INBOX_ALLOWED_MEMBER'] == 'true') {
        final partnerRole = role == 'admin' ? 'manager' : 'admin';
        final account = (h.fixture['accounts'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((a) => a['role'] == partnerRole);
        final partner =
            (await h.scope
                    .read(magicProfileAdminServiceProvider)
                    .listProfiles(q: account['email']))
                .singleWhere((p) => p['email'] == account['email']);
        memberName = '${partner['first_name']} ${partner['last_name']}';
        memberUser = partner['user_id'];
        memberProfile = partner['id'];
      }
      final allowedMember =
          Platform.environment['INBOX_ALLOWED_MEMBER'] == 'true';
      Future<void> check(
        String id,
        String description,
        Future<void> Function() body,
      ) async {
        if ({
              'DIRECT-FROM-MEMBER',
              'DIRECT-HEADER',
              'PROFILE-NOTE',
            }.contains(id) &&
            !allowedMember)
          return;
        if (Platform.environment['INBOX_LINKS_ONLY'] == 'true' &&
            !{
              'DIRECT-FROM-MEMBER',
              'DIRECT-HEADER',
              'PROFILE-NOTE',
            }.contains(id))
          return;
        await h.check(id, description, body);
      }

      final pages = <Map<String, dynamic>>[];
      h.api.rawDio.interceptors.add(
        InterceptorsWrapper(
          onResponse: (r, handler) {
            if (r.requestOptions.uri.path.endsWith('/messenger/chats'))
              pages.add({
                'step': h.currentStep,
                'query': Map<String, dynamic>.from(
                  r.requestOptions.queryParameters,
                ),
                'ids': ((r.data as Map)['items'] as List)
                    .map((x) => x['id'])
                    .toList(),
              });
            handler.next(r);
          },
        ),
      );
      Future<void> open() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(const StaffWorkspaceScreen());
        await h.quiet();
      }

      Future<void> folder(String name) async {
        await h.tap(
          find.descendant(
            of: find.byType(InboxFolderBar),
            matching: find.text(name),
          ),
        );
        await h.quiet();
      }

      Future<void> search(String q) async {
        final field = find
            .descendant(
              of: find.byType(ChatSearchBar),
              matching: find.byType(TextField),
            )
            .first;
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await h.tap(field);
        await tester.enterText(field, q);
        await h.quiet();
      }

      Future<void> action(String text) async {
        await h.tap(find.byTooltip('Действия с чатом'));
        await h.tap(find.text(text));
        await h.quiet();
      }

      Future<Map<String, dynamic>> current() async {
        final rows = [
          ...await svc.listChats(),
          ...await svc.listChats(archived: true),
        ];
        final row = rows.firstWhere((r) => r['id'] == inbox);
        h.facts.add({'step': h.currentStep, 'chat': row});
        return row;
      }

      Future<void> inboxOpen() async {
        await open();
        await folder('Ученики');
        await h.tap(find.text('Student0 HTTP test').first);
        await h.quiet();
      }

      Future<void> info(String title) async {
        await h.tap(
          find.descendant(
            of: find.byType(ChatHeader),
            matching: find.text(title),
          ),
        );
        await h.quiet();
        expect(find.byType(ChatInfoDialog), findsOneWidget);
      }

      await check(
        'OPEN-PAGES',
        'Открыть 105 групп и обращение: реальные страницы загружаются полностью',
        () async {
          await open();
          expect(pages.any((p) => (p['query'] as Map)['cursor'] != null), true);
          final loaded = pages
              .expand((p) => (p['ids'] as List).cast<String>())
              .toSet();
          expect(
            loaded.containsAll((h.fixture['groupIds'] as List).cast<String>()),
            true,
          );
        },
      );
      await check('SEARCH', 'Поиск находит чат со второй страницы', () async {
        await search('AUDIT-PAGING-001');
        expect(find.text('AUDIT-PAGING-001'), findsWidgets);
      });
      await check(
        'SEARCH-EMPTY',
        'Отсутствующий чат и очистка поиска',
        () async {
          await search('AUDIT-NOT-FOUND');
          expect(find.text('AUDIT-PAGING-001'), findsNothing);
          await search('');
        },
      );
      await check('FOLDERS', 'Переключить Лиды, Ученики и Архив', () async {
        await folder('Ученики');
        expect(find.text('Student0 HTTP test'), findsWidgets);
        await folder('Лиды');
        expect(find.text('Student0 HTTP test'), findsNothing);
        await folder('Архив');
        expect(find.text('Student0 HTTP test'), findsNothing);
        await folder('Ученики');
      });
      await check(
        'BRANCH',
        'Фильтр филиала сохраняет обращение своего филиала',
        () async {
          final field = find.byType(DropdownButton<String?>);
          await h.tap(field);
          await h.tap(find.text('HTTP test').last);
          await h.quiet();
          expect(find.text('Student0 HTTP test'), findsWidgets);
          expect(
            (pages.last['query'] as Map)['branchId'],
            h.fixture['branchId'],
          );
        },
      );
      await check(
        'ASSIGN',
        'Взять обращение в работу и сразу увидеть действие снятия назначения',
        () async {
          await h.tap(find.text('Student0 HTTP test').first);
          await h.quiet();
          await action('Взять в работу');
          expect((await current())['assigned_to'], isNotNull);
          await h.tap(find.byTooltip('Действия с чатом'));
          try {
            expect(find.text('Снять с работы'), findsOneWidget);
          } finally {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await h.quiet();
          }
        },
      );
      await check(
        'UNASSIGN',
        'После повторного открытия снять своё назначение',
        () async {
          await inboxOpen();
          await action('Снять с работы');
          expect((await current())['assigned_to'], isNull);
        },
      );
      await check('ARCHIVE', 'Архивировать обращение через шапку', () async {
        await inboxOpen();
        await action('В архив');
        expect((await current())['archived'], true);
      });
      await check(
        'ARCHIVE-REOPEN',
        'Открыть архив после повторного входа в раздел',
        () async {
          await open();
          await folder('Архив');
          expect(find.text('Student0 HTTP test'), findsWidgets);
          await h.tap(find.text('Student0 HTTP test').first);
          await h.quiet();
        },
      );
      await check('UNARCHIVE', 'Вернуть обращение из архива', () async {
        await action('Вернуть из архива');
        expect((await current())['archived'], false);
        await folder('Ученики');
        expect(find.text('Student0 HTTP test'), findsWidgets);
      });
      if (!allowedMember)
        await check(
          'MEMBER-LINK-HIDDEN',
          'Участник вне области доступа не предлагает открыть личный чат',
          () async {
            await open();
            await search('AUDIT-PAGING-001');
            await h.tap(
              find
                  .byWidgetPredicate(
                    (w) => w is Text && w.data == 'AUDIT-PAGING-001',
                  )
                  .first,
            );
            await h.quiet();
            await info('AUDIT-PAGING-001');
            final row = find
                .ancestor(
                  of: find.descendant(
                    of: find.byType(ChatInfoDialog),
                    matching: find.text(memberName),
                  ),
                  matching: find.byType(Row),
                )
                .first;
            expect(
              find.descendant(of: row, matching: find.byTooltip('Открыть чат')),
              findsNothing,
            );
          },
        );
      await check(
        'DIRECT-FROM-MEMBER',
        'Начать личный чат с участником группы',
        () async {
          await open();
          await search('AUDIT-PAGING-001');
          await h.tap(
            find
                .byWidgetPredicate(
                  (w) => w is Text && w.data == 'AUDIT-PAGING-001',
                )
                .first,
          );
          await h.quiet();
          await info('AUDIT-PAGING-001');
          final row = find
              .ancestor(
                of: find.descendant(
                  of: find.byType(ChatInfoDialog),
                  matching: find.text(memberName),
                ),
                matching: find.byType(Row),
              )
              .first;
          await h.tap(
            find.descendant(of: row, matching: find.byTooltip('Открыть чат')),
          );
          await h.quiet();
          final chats = await svc.listChats();
          h.facts.add({
            'step': h.currentStep,
            'chats': chats.where((c) => c['raw_type'] == 'direct').toList(),
            'memberUser': memberUser,
          });
          expect(
            chats.any(
              (c) => c['raw_type'] == 'direct' && c['partner_id'] == memberUser,
            ),
            true,
          );
        },
      );
      await check(
        'DIRECT-HEADER',
        'Сразу после перехода шапка показывает имя собеседника',
        () async {
          final actual = tester
              .widget<ChatHeader>(find.byType(ChatHeader))
              .title;
          h.facts.add({
            'step': h.currentStep,
            'actualTitle': actual,
            'expectedTitle': memberName,
          });
          expect(actual, memberName);
        },
      );
      await check(
        'PROFILE-NOTE',
        'Добавить заметку профиля из сведений личного чата',
        () async {
          await info(tester.widget<ChatHeader>(find.byType(ChatHeader)).title);
          await h.tap(find.text('Заметки'));
          await h.quiet();
          if (find.text('Добавить первую').evaluate().isNotEmpty) {
            await h.tap(find.text('Добавить первую'));
          } else {
            await h.tap(find.byTooltip('Добавить заметку'));
          }
          final field = find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.hintText == 'Введите текст заметки',
          );
          await tester.enterText(field, 'AUDIT-PROFILE-NOTE-$role');
          await h.tap(find.widgetWithText(ElevatedButton, 'Добавить'));
          await h.quiet();
          final notes = await h.scope
              .read(magicProfileAdminServiceProvider)
              .listProfileNotes(memberProfile);
          h.facts.add({
            'step': h.currentStep,
            'notes': notes,
            'memberProfile': memberProfile,
          });
          expect(
            notes.any((n) => n['body'] == 'AUDIT-PROFILE-NOTE-$role'),
            true,
          );
          expect(find.text('AUDIT-PROFILE-NOTE-$role'), findsWidgets);
        },
      );
      await check(
        'CONTACT-LINK',
        'Из обращения открыть существующую карточку ученика',
        () async {
          await open();
          await folder('Ученики');
          await h.tap(find.text('Student0 HTTP test').first);
          await h.quiet();
          await h.tap(find.byTooltip('Открыть карточку клиента'));
          await h.quiet();
          expect(find.byType(ClientCard), findsOneWidget);
        },
      );
      h.facts.add({'pages': pages});
      await h.finish();
    });
}
