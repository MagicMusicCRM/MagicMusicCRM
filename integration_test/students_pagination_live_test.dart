import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_students_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_card.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['teacher', 'admin', 'manager', 'director']) {
    testWidgets('$role actual student pagination', (tester) async {
      final h = LiveAuditHarness(tester, role, 'students-pagination');
      await h.initialize(size: const Size(1600, 1200));
      final pages = <Map<String, dynamic>>[];
      h.api.rawDio.interceptors.add(
        InterceptorsWrapper(
          onResponse: (r, handler) {
            if (r.requestOptions.uri.path.endsWith('/students/search')) {
              final d = r.data as Map;
              pages.add({
                'step': h.currentStep,
                'query': Map<String, dynamic>.from(
                  r.requestOptions.queryParameters,
                ),
                'ids': (d['items'] as List).map((x) => x['id']).toList(),
                'nextCursor': d['nextCursor'],
              });
            }
            handler.next(r);
          },
        ),
      );
      Future<void> open() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(
          Scaffold(
            body: role == 'teacher'
                ? const TeacherStudentsWidget()
                : const StudentsBoardWidget(),
          ),
        );
        await h.quiet();
      }

      Finder key(String k) => find.byKey(ValueKey(k));
      Future<void> search(String q) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await h.tap(key('students-search'));
        await tester.enterText(key('students-search'), q);
        await h.quiet();
      }

      final expected =
          (h.fixture[role == 'teacher' ? 'teacherStudents' : 'allStudents']
                  as List)
              .cast<String>()
              .toSet();
      await h.check(
        'OPEN',
        'Первая страница содержит 100 учеников и cursor',
        () async {
          await open();
          expect(pages.first['ids'], hasLength(100));
          expect(pages.first['nextCursor'], isNotNull);
        },
      );
      if (role != 'teacher') {
        await h.check(
          'SEARCH-UNLOADED',
          'Найти существующего ученика за пределами первых 100 записей',
          () async {
            expect(
              (pages.first['ids'] as List).contains(h.fixture['oldestStudent']),
              false,
            );
            await search('AUDIT-PAGE-001');
            expect(
              find.widgetWithText(StudentBoardCard, 'AUDIT-PAGE-001'),
              findsOneWidget,
            );
          },
        );
        await h.check(
          'SEARCH-CLEAR',
          'Очистка поиска возвращает первую страницу',
          () async {
            await h.tap(find.byTooltip('Очистить поиск'));
            await h.quiet();
            expect(find.byType(StudentBoardCard), findsWidgets);
          },
        );
      }
      await h.check(
        'NEXT-PAGE',
        'Колесо прокрутки загружает все оставшиеся записи без повторов',
        () async {
          // Keep the observed first page: remounting can reuse Riverpod's cached data.
          Finder list = role == 'teacher'
              ? find.descendant(
                  of: find.byType(TeacherStudentsWidget),
                  matching: find.byType(ListView),
                )
              : find.byWidgetPredicate(
                  (w) =>
                      w is ListView &&
                      w.key is PageStorageKey &&
                      (w.key as PageStorageKey).value.toString().startsWith(
                        'students_col_',
                      ),
                );
          list = list.first;
          for (
            var i = 0;
            i < 30 && !pages.any((p) => (p['query'] as Map)['cursor'] != null);
            i++
          ) {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: tester.getCenter(list),
                scrollDelta: const Offset(0, 2000),
              ),
            );
            await h.quiet();
          }
          expect(pages.any((p) => (p['query'] as Map)['cursor'] != null), true);
          final paginationPages = pages.where((p) {
            final query = p['query'] as Map;
            return (query['q']?.toString().isEmpty ?? true);
          });
          final ids = paginationPages
              .expand((p) => (p['ids'] as List).cast<String>())
              .toList();
          expect(ids.toSet(), expected);
          expect(ids.length, expected.length);
        },
      );
      if (role != 'teacher')
        await h.check(
          'SEARCH-LOADED',
          'После загрузки страниц тот же ученик находится',
          () async {
            await search('AUDIT-PAGE-001');
            expect(
              find.widgetWithText(StudentBoardCard, 'AUDIT-PAGE-001'),
              findsOneWidget,
            );
          },
        );
      h.facts.add({'pages': pages, 'expectedIds': expected.toList()});
      await h.finish();
    });
  }
}
