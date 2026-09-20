import 'package:dio/dio.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/workspace/magic_context_bar.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets('$role actual client boards', (tester) async {
      final h = LiveAuditHarness(tester, role, 'boards');
      await h.initialize(size: const Size(1600, 1400));
      final queries = <Map<String, dynamic>>[];
      h.api.rawDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, handler) {
            if (o.method == 'GET')
              queries.add({
                'path': o.uri.path,
                'query': Map<String, dynamic>.from(o.queryParameters),
                'step': h.currentStep,
              });
            handler.next(o);
          },
        ),
      );
      Finder key(String k) => find.byKey(ValueKey(k));
      Map last(String path) =>
          queries.lastWhere(
                (q) => (q['path'] as String).contains(path),
              )['query']
              as Map;
      Future<void> search(String k, String q) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await h.tap(key(k));
        await tester.enterText(key(k), q);
        await tester.pump();
        expect(tester.widget<EditableText>(find.descendant(of: key(k), matching: find.byType(EditableText))).controller.text, q);
        await h.quiet();
      }

      Future<void> leadDropdown(String label, String chosen) async {
        final field = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              (w.key as ValueKey?)?.value.toString().startsWith('$label:') ==
                  true,
        );
        await h.tap(field);
        await h.tap(find.text(chosen).last);
        await h.quiet();
      }

      final openOnly = Platform.environment['BOARDS_AUDIT_OPEN_ONLY'] == 'true';
      if (!openOnly) {
      await h.check(
        'OPEN',
        'Открыть доску лидов с 32 синтетическими карточками',
        () async {
          await h.mount(StaffWorkspaceScreen(initialLink: EntityRouteRegistry.sectionRootLink('clients')));
          await h.quiet();
          expect(key('leads-search'), findsOneWidget);
          expect(find.text('AUDIT-LEAD-032'), findsOneWidget);
        },
      );
      await h.check(
        'LEAD-SEARCH',
        'Поиск находит карточку за пределами первой страницы',
        () async {
          await search('leads-search', 'AUDIT-LEAD-001');
          expect(find.text('AUDIT-LEAD-001', skipOffstage: true).evaluate().where((e) => e.widget is Text).length, 1);
          expect(
            last('/leads/board')['q'].toString().toLowerCase(),
            'audit-lead-001',
          );
        },
      );
      await h.check(
        'LEAD-EMPTY',
        'Поиск отсутствующего лида показывает пустой результат',
        () async {
          await search('leads-search', 'AUDIT-NOT-FOUND');
          expect(find.textContaining('Ничего не найдено'), findsWidgets);
        },
      );
      await h.check('LEAD-CLEAR', 'Очистить поиск и вернуть доску', () async {
        await h.tap(find.byTooltip('Очистить поиск'));
        await h.quiet();
        expect(find.text('AUDIT-LEAD-032'), findsOneWidget);
      });
      await h.check(
        'LEAD-PAGE',
        'Прокрутка колонки загружает следующую страницу',
        () async {
          final list = find.byKey(
            PageStorageKey('leads_col_${h.fixture['leadStatus']}'),
          );
          await h.tap(find.text('Фильтры'));
          await leadDropdown('Сортировка', 'Сначала старые');
          await h.tap(find.text('Свернуть'));
          for (
            var i = 0;
            i < 10 &&
                !queries.any(
                  (q) =>
                      (q['path'] as String).contains('/leads/board') &&
                      (q['query'] as Map)['cursor'] != null,
                );
            i++
          ) {
            await tester.sendEventToBinding(PointerScrollEvent(position: tester.getCenter(list), scrollDelta: const Offset(0, 1600)));
            await h.quiet();
          }
          expect(
            queries.any(
              (q) =>
                  (q['path'] as String).contains('/leads/board') &&
                  (q['query'] as Map)['cursor'] != null,
            ),
            true,
          );
        },
      );
      await h.check(
        'LEAD-BRANCH',
        'Фильтр филиала передаёт реальный branchId',
        () async {
          await h.tap(find.text('Фильтры'));
          await leadDropdown('Филиал', 'HTTP test');
          expect(last('/leads/board')['branchId'], h.fixture['branchId']);
        },
      );
      await h.check(
        'LEAD-TASKS',
        'Фильтр наличия задач применяется и снимается',
        () async {
          await h.tap(find.text('Есть задачи'));
          await h.quiet();
          expect(last('/leads/board')['openTasks'], true);
          await h.tap(find.text('Есть задачи'));
          await h.quiet();
          expect(last('/leads/board')['openTasks'], isNot(true));
        },
      );
      await h.check(
        'LEAD-RESET',
        'Сбросить фильтры филиала и сортировки',
        () async {
          await h.tap(find.text('Сбросить'));
          await h.quiet();
          expect(last('/leads/board')['branchId'], isNull);
          expect(last('/leads/board')['sort'], 'newest');
          await h.tap(find.text('Свернуть'));
        },
      );
      await h.check('STUDENTS', 'Переключиться на учеников', () async {
        await h.tap(find.text('Ученики').first);
        await h.quiet();
        expect(key('students-search'), findsOneWidget);
        expect(find.byType(StudentBoardCard), findsWidgets);
      });
      await h.check(
        'STUDENT-SEARCH',
        'Поиск ученика по имени и очистка',
        () async {
          await search('students-search', 'Student0');
          expect(find.text('Student0 HTTP test'), findsOneWidget);
          await search('students-search', 'AUDIT-NOT-FOUND');
          expect(find.byType(StudentBoardCard), findsNothing);
          await h.tap(find.byTooltip('Очистить поиск'));
          await h.quiet();
          expect(find.byType(StudentBoardCard), findsWidgets);
        },
      );
      await h.check(
        'STUDENT-BRANCH',
        'Без филиала и возврат в исходный филиал',
        () async {
          await h.tap(find.text('Фильтры'));
          final field = find.descendant(
            of: key('students-filters-panel'),
            matching: find.byType(DropdownButtonFormField<String>),
          );
          await h.tap(field);
          await h.tap(find.text('Без филиала').last);
          await h.quiet();
          expect(last('/students/search')['noBranch'], true);
          await h.tap(field);
          await h.tap(find.text('HTTP test').last);
          await h.quiet();
          expect(last('/students/search')['branchId'], h.fixture['branchId']);
        },
      );
      }
      if (openOnly) {
        await h.mount(StaffWorkspaceScreen(initialLink: EntityRouteRegistry.sectionRootLink('clients')));
        await h.quiet();
        await h.tap(find.text('Ученики').first);
        await h.quiet();
      }
      await h.check(
        'STUDENT-OPEN',
        'Открыть карточку из доски и вернуться',
        () async {
          await search('students-search', 'Student0');
          await h.tap(find.text('Student0 HTTP test'));
          await h.quiet();
          expect(find.byType(ClientCard), findsOneWidget);
          await h.tap(find.descendant(of: find.byType(MagicContextBar), matching: find.widgetWithText(TextButton, 'Клиенты')));
          await h.quiet();
          expect(key('clients-workspace-canvas'), findsOneWidget);
          h.facts.add({'step': 'STUDENT-OPEN', 'returnShowsLeads': key('leads-search').evaluate().isNotEmpty});
        },
      );
      h.facts.add({'queries': queries});
      await h.finish();
    });
  }
}
