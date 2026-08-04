import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_schedule_calendar.dart';

import '../test/features/crm/client_card/card_fake_api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('client calendar drills into schedule and Back restores it', (
    tester,
  ) async {
    final api = FakeCardApiClient(
      scheduleMatrix: const [
        {
          'id': 'lesson-device',
          'studentId': 'student-1',
          'studentName': 'Анна Смирнова',
          'branchId': 'branch-a',
          'scheduledAt': '2026-08-04T12:00:00.000Z',
          'durationMinutes': 60,
          'status': 'scheduled',
          'lifecycleState': 'scheduled',
          'isTrial': true,
          'conflictTypes': ['room_overlap'],
        },
      ],
    );
    final router = GoRouter(
      initialLocation: '/students/student-1',
      routes: [
        GoRoute(
          path: '/students/:id',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              child: ClientScheduleCalendar(
                clientType: 'student',
                clientId: 'student-1',
                clientName: 'Анна Смирнова',
                branches: const [
                  {'id': 'branch-a', 'name': 'Сокол', 'utcOffsetMinutes': 180},
                ],
                defaultBranchId: 'branch-a',
                canRead: true,
                initialViewState: ContextViewState(
                  filters: const {
                    'section': 'lessons',
                    'clientCalendarMode': 'day',
                    'clientCalendarBranchId': 'branch-a',
                  },
                  date: DateTime(2026, 8, 4),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/admin',
          builder: (_, _) => const Scaffold(body: Text('Расписание host')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          capabilitySnapshotProvider.overrideWith(
            (ref) async => const CapabilitySnapshot(
              accountId: 'account-1',
              role: 'admin',
              accessVersion: 1,
              capabilities: {'crm.client.read.basic', 'schedule.lesson.write'},
              scopes: {'schedule': 'branch'},
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Клиент карточки'), findsOneWidget);
    expect(find.text('Другие клиенты'), findsOneWidget);
    final lesson = find.byKey(
      const ValueKey('client-calendar-lesson-lesson-device'),
    );
    await tester.ensureVisible(lesson);
    await tester.pumpAndSettle();
    await tester.tap(lesson);
    await tester.pumpAndSettle();
    expect(find.text('Расписание host'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('client-calendar-grid')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
