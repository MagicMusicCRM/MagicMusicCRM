import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/clients_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/manager_overview_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/shared_tasks_v4_panel.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';

import 'messenger_test_api.dart';

CapabilitySnapshot _staffSnapshot(String role) {
  final capabilities = <String>{
    'crm.client.read.basic',
    'crm.client.write',
    'schedule.lesson.read.assigned',
    'schedule.lesson.write',
    'workflow.task.read',
    'workflow.task.write',
  };
  if (role == 'manager') {
    capabilities.addAll({'report.status.read', 'system.settings.manage'});
  }
  return CapabilitySnapshot(
    accountId: 'test-$role',
    role: role,
    accessVersion: 1,
    capabilities: capabilities,
    scopes: const {'client': 'branch', 'schedule': 'branch'},
  );
}

Future<void> _pumpStaffMessenger(
  WidgetTester tester, {
  required String role,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        magicApiClientProvider.overrideWithValue(
          RecordingFakeApiClient(profileRole: role),
        ),
        capabilitySnapshotProvider.overrideWith(
          (ref) async => _staffSnapshot(role),
        ),
      ],
      child: MaterialApp(home: MessengerScreen(role: role)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets('manager can open Tasks from the mobile overflow navigation', (
    tester,
  ) async {
    await _pumpStaffMessenger(tester, role: 'manager');

    expect(find.text('Ещё'), findsOneWidget);
    await tester.tap(find.text('Ещё'));
    await tester.pumpAndSettle();

    expect(find.text('Задачи'), findsOneWidget);
    await tester.tap(find.text('Задачи'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byType(SharedTasksV4Panel), findsOneWidget);
  });

  testWidgets('manager Overview Tasks action opens Tasks instead of Clients', (
    tester,
  ) async {
    await _pumpStaffMessenger(tester, role: 'manager');

    await tester.tap(find.text('Обзор'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final openTasks = find.text('Открытые задачи');
    expect(openTasks, findsOneWidget);
    await tester.ensureVisible(openTasks);
    // Messenger keeps realtime/timer work alive; a bounded pump is enough for
    // the overview scroll animation and cannot hang like pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(openTasks);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byType(SharedTasksV4Panel), findsOneWidget);
    expect(find.byType(ClientsWidget), findsNothing);
  });

  testWidgets('admin keeps the direct mobile Tasks destination', (
    tester,
  ) async {
    await _pumpStaffMessenger(tester, role: 'admin');

    expect(find.text('Задачи'), findsOneWidget);
    await tester.tap(find.text('Задачи'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byType(SharedTasksV4Panel), findsOneWidget);
  });

  testWidgets('manager Overview KPI callbacks use canonical destinations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    int? target;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(
            RecordingFakeApiClient(profileRole: 'manager'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ManagerOverviewWidget(
              role: 'manager',
              onTabChange: (index, _) => target = index,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    Future<void> expectTarget(String label, int expected) async {
      final match = find.text(label).last;
      await tester.ensureVisible(match);
      await tester.pump(const Duration(milliseconds: 250));
      target = null;
      await tester.tap(match);
      await tester.pump();
      expect(
        target,
        expected,
        reason: '$label must target canonical tab $expected',
      );
    }

    await expectTarget('Ученики с долгом', 3);
    await expectTarget('Активные ученики', 3);
    await expectTarget('Новые лиды', 3);
    await expectTarget('Открытые задачи', 6);
    await expectTarget('Просроченные задачи', 6);
    await expectTarget('Пробные занятия', 2);
    await expectTarget('Конфликты расписания', 2);
    await expectTarget('Загрузка аудиторий', 7);
    await expectTarget('Действия сотрудников', 7);
  });
}
