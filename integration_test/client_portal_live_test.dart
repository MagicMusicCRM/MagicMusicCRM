import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/client/presentation/screens/client_dashboard_screen.dart';
import 'package:magic_music_crm/features/client/presentation/screens/client_portal_screen.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/subscription_status_card.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/upcoming_lessons_list.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets(
    'Client linked students, lessons and homework submission',
    (tester) async {
      final h = LiveAuditHarness(tester, 'client', 'portal');
      await h.initialize(size: const Size(1280, 1000));
      final crm = h.scope.read(magicCrmServiceProvider);
      final expectedIds = (h.fixture['students'] as List).cast<String>();
      final expectedSubs = (h.fixture['subscriptions'] as List).cast<String>();
      final homeworks = (h.fixture['homeworks'] as List)
          .cast<Map<String, dynamic>>();
      await h.check(
        'PORTAL-OPEN',
        'Открыть «Моя школа» из настоящего кабинета клиента',
        () async {
          await h.mount(const ClientDashboardScreen());
          await h.quiet();
          await h.tap(find.byTooltip('Моя школа'));
          await h.waitFor(
            () => find.byType(ClientPortalScreen).evaluate().isNotEmpty,
            'Portal opened',
          );
          await h.scope.read(myStudentsProvider.future);
          await h.quiet();
        },
      );
      final students = await crm.listMyStudents();
      await h.check(
        'PORTAL-LINKED-STUDENTS',
        'Клиент видит собственного и явно привязанного ученика',
        () async {
          expect(students.map((row) => row['id']).toSet(), expectedIds.toSet());
          final commerce = await h.scope.read(
            myCommerceProjectionProvider.future,
          );
          expect(
            commerce.students.map((row) => row.studentId).toSet(),
            expectedIds.toSet(),
          );
          expect(find.byType(ChoiceChip), findsNWidgets(2));
          h.facts.add({
            'step': h.currentStep,
            'students': students,
            'commerceIds': commerce.students
                .map((row) => row.studentId)
                .toList(),
          });
        },
      );
      for (var index = 0; index < expectedIds.length; index++) {
        final id = expectedIds[index];
        final student = students.singleWhere((row) => row['id'] == id);
        final name = '${student['first_name']} ${student['last_name']}'.trim();
        await h.check(
          'PORTAL-STUDENT-$index',
          'Переключить ученика: абонемент и предстоящие занятия',
          () async {
            await h.tap(find.widgetWithText(ChoiceChip, name));
            await h.quiet();
            expect(
              await h.scope.read(magicCurrentStudentIdProvider.future),
              id,
            );
            final subscription = await h.scope.read(
              subscriptionProvider.future,
            );
            h.facts.add({
              'step': h.currentStep,
              'studentId': id,
              'subscription': subscription,
            });
            expect(subscription?['id'], expectedSubs[index]);
            final upcoming = await h.scope.read(
              upcomingLessonsRichProvider.future,
            );
            expect(upcoming.every((row) => row['student_id'] == id), isTrue);
            h.facts.add({
              'step': h.currentStep,
              'studentId': id,
              'subscription': subscription,
              'upcoming': upcoming,
            });
            expect(
              tester
                  .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, name))
                  .selected,
              isTrue,
            );
          },
        );
        await h.check(
          'PORTAL-HISTORY-$index',
          'История занятий относится к выбранному ученику',
          () async {
            await h.tap(find.text('История'));
            final history = await h.scope.read(pastLessonsRichProvider.future);
            expect(history.every((row) => row['student_id'] == id), isTrue);
            h.facts.add({
              'step': h.currentStep,
              'studentId': id,
              'history': history,
            });
            await h.tap(find.text('Предстоящие'));
          },
        );
      }
      await h.check(
        'PORTAL-REFRESH',
        'Обновление повторно запрашивает занятия и сохраняет выбор ученика',
        () async {
          final before = h.requests.length;
          await h.tap(find.byTooltip('Обновить'));
          await h.quiet();
          expect(
            h.requests
                .skip(before)
                .any(
                  (r) =>
                      r['method'] == 'GET' && r['path'] == '/api/crm/lessons',
                ),
            isTrue,
          );
          expect(
            await h.scope.read(magicCurrentStudentIdProvider.future),
            expectedIds.last,
          );
        },
      );
      Finder homeworkCard(String title) => find
          .ancestor(of: find.text(title), matching: find.byType(Container))
          .first;
      await h.check(
        'PORTAL-HOMEWORKS',
        'Открыть задания доступных клиенту учеников',
        () async {
          await h.tap(find.text('Задания'));
          await h.quiet();
          final rows = await crm.listHomeworks();
          expect(
            rows.map((row) => row['id']).toSet(),
            homeworks.map((row) => row['id']).toSet(),
          );
          h.facts.add({'step': h.currentStep, 'homeworks': rows});
          for (final homework in homeworks) {
            expect(find.text(homework['title'] as String), findsOneWidget);
          }
        },
      );
      final target = homeworks.first;
      Finder submitButton() => find.descendant(
        of: homeworkCard(target['title'] as String),
        matching: find.widgetWithText(ElevatedButton, 'Сдать'),
      );
      await h.check(
        'PORTAL-HOMEWORK-CANCEL',
        'Отмена сдачи сохраняет статус assigned',
        () async {
          await h.tap(submitButton());
          await h.tap(find.byKey(const ValueKey('magic-modal-close')));
          await h.quiet();
          final row = (await crm.listHomeworks()).singleWhere(
            (row) => row['id'] == target['id'],
          );
          expect(row['status'], 'assigned');
        },
      );
      await h.check(
        'PORTAL-HOMEWORK-SUBMIT',
        'Сдать задание без файла и увидеть сохранённый статус',
        () async {
          await h.tap(submitButton());
          await h.tap(
            find.byKey(const ValueKey('homework-submit-without-file')),
          );
          await h.quiet();
          final rows = await crm.listHomeworks();
          expect(
            rows.singleWhere((row) => row['id'] == target['id'])['status'],
            'submitted',
          );
          expect(
            rows.singleWhere((row) => row['id'] != target['id'])['status'],
            'assigned',
          );
          expect(
            find.descendant(
              of: homeworkCard(target['title'] as String),
              matching: find.text('Сдано'),
            ),
            findsOneWidget,
          );
          expect(submitButton(), findsNothing);
          h.facts.add({'step': h.currentStep, 'homeworks': rows});
        },
      );
      await h.check(
        'PORTAL-HOMEWORK-REOPEN',
        'Повторное открытие заданий сохраняет результат сдачи',
        () async {
          await h.tap(find.text('Предстоящие'));
          await h.tap(find.text('Задания'));
          await h.quiet();
          expect(
            find.descendant(
              of: homeworkCard(target['title'] as String),
              matching: find.text('Сдано'),
            ),
            findsOneWidget,
          );
          expect(submitButton(), findsNothing);
        },
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
