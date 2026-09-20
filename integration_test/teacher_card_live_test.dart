import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_api.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/teacher_client_card.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_students_widget.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets(
    'Teacher list opens scoped educational card',
    (tester) async {
      final h = LiveAuditHarness(tester, 'teacher', 'teacher-card');
      await h.initialize(size: const Size(1440, 1100));
      final studentId = h.fixture['studentId'] as String;
      Map<String, dynamic>? card;
      await h.check('NAV', 'Рабочее пространство → Ученики', () async {
        await h.mount(const StaffWorkspaceScreen());
        await h.tap(find.text('Ученики').first);
        await h.waitFor(
          () => find.byType(TeacherStudentsWidget).evaluate().isNotEmpty,
          'Teacher students section mounted',
        );
        await h.quiet();
      });
      await h.check(
        'LIST',
        'Назначенный ученик присутствует в реальном списке преподавателя',
        () async {
          await h.waitFor(
            () => find
                .byKey(ValueKey('teacher-student-$studentId'))
                .evaluate()
                .isNotEmpty,
            'Assigned student row loaded',
          );
          expect(find.text('Нет прикреплённых учеников'), findsNothing);
        },
      );
      final cardRequestStart = h.requests.length;
      await h.check(
        'OPEN',
        'Открыть учебную карточку нажатием на ученика',
        () async {
          await h.tap(find.byKey(ValueKey('teacher-student-$studentId')));
          await h.waitFor(
            () => find.byType(TeacherClientCard).evaluate().isNotEmpty,
            'Actual routed teacher card opened',
          );
          await h.waitFor(
            () => find
                .byKey(const ValueKey('teacher-section-lessons'))
                .evaluate()
                .isNotEmpty,
            'Educational sections loaded',
          );
          card = await h.scope
              .read(clientCardApiProvider)
              .loadCard(entityType: 'student', entityId: studentId);
          h.facts.add({
            'step': h.currentStep,
            'studentId': studentId,
            'card': card,
          });
          expect(
            find.text((card!['header'] as Map)['displayName'] as String),
            findsWidgets,
          );
        },
      );
      if (card == null) {
        h.blocked('LESSONS', 'Занятия в учебной карточке', 'Card did not open');
        h.blocked(
          'HOMEWORK',
          'Домашние задания в учебной карточке',
          'Card did not open',
        );
        h.blocked('COMMENTS', 'Видимость комментариев', 'Card did not open');
        h.blocked(
          'READONLY',
          'Ограниченная учебная карточка',
          'Card did not open',
        );
      } else {
        List<Map<String, dynamic>> items(String key) =>
            ((card!['sections'] as Map)[key]['items'] as List)
                .map((r) => Map<String, dynamic>.from(r as Map))
                .toList();
        await h.check(
          'LESSONS',
          'Карточка содержит только занятия этого преподавателя',
          () async {
            final lessons = items('lessons');
            final expected = (h.fixture['ownLessons'] as List).cast<String>();
            expect(
              lessons.map((r) => r['id']).toList(),
              unorderedEquals(expected),
            );
            expect(lessons, isNotEmpty);
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('teacher-section-lessons')),
                matching: find.byType(ListTile),
              ),
              findsWidgets,
            );
          },
        );
        await h.check(
          'HOMEWORK',
          'Домашние задания: своё занятие видно, задание другого преподавателя скрыто',
          () async {
            await h.tap(find.widgetWithText(ChoiceChip, 'Домашние задания'));
            expect(
              items('homework').map((r) => r['id']),
              contains(h.fixture['ownHomework']),
            );
            expect(
              items('homework').map((r) => r['id']),
              isNot(contains(h.fixture['otherHomework'])),
            );
            expect(find.text('TEACHER-OWN-HOMEWORK'), findsOneWidget);
            expect(find.text('TEACHER-OTHER-HOMEWORK'), findsNothing);
          },
        );
        await h.check(
          'COMMENTS',
          'Показанный преподавателю комментарий виден, внутренний скрыт',
          () async {
            await h.tap(find.widgetWithText(ChoiceChip, 'Комментарии'));
            expect(
              items('comments').map((r) => r['id']),
              contains(h.fixture['sharedComment']),
            );
            expect(
              items('comments').map((r) => r['id']),
              isNot(contains(h.fixture['privateComment'])),
            );
            expect(find.text('TEACHER-SHARED-COMMENT'), findsOneWidget);
            expect(find.text('TEACHER-PRIVATE-COMMENT'), findsNothing);
          },
        );
        await h.check(
          'READONLY',
          'Учебная карточка не предлагает финансовые и staff-команды',
          () async {
            expect((card!['sections'] as Map).containsKey('finance'), isFalse);
            final surface = find.byType(TeacherClientCard);
            expect(
              find.descendant(of: surface, matching: find.byType(TextField)),
              findsNothing,
            );
            expect(
              find.descendant(
                of: surface,
                matching: find.text('Продать абонемент'),
              ),
              findsNothing,
            );
            expect(
              find.descendant(
                of: surface,
                matching: find.text('Прикрепить к ученику'),
              ),
              findsNothing,
            );
            expect(
              h.requests.skip(cardRequestStart).where(
                (r) =>
                    r['method'] != 'GET' &&
                    !(r['path'] as String).contains('/auth/') &&
                    !(r['path'] as String).endsWith('/sections/seen'),
              ),
              isEmpty,
            );
          },
        );
      }
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
