import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_panel.dart';
import 'package:magic_music_crm/shared/widgets/audit_event_card.dart';

import 'card_fake_api.dart';
import 'client_card_desktop_editing_test.dart'
    show desktopManager, desktopStudent;

// Includes the full-width imported fields missing from the original visual fixture.
const densityFields = [
  {
    'entity': 'students',
    'key': 'category',
    'label': 'Категория обучения',
    'type': 'select',
    'options': ['Взрослые'],
  },
  {'entity': 'students', 'key': 'requestType', 'label': 'Тип обращения'},
  {
    'entity': 'students',
    'key': 'lessonType',
    'label': 'Тип обучения',
    'type': 'select',
    'options': ['Индивидуальное'],
  },
  {
    'entity': 'students',
    'key': 'level',
    'label': 'Уровень',
    'type': 'select',
    'options': ['Начальный'],
  },
  {'entity': 'students', 'key': 'learningGoal', 'label': 'Цель обучения'},
];

FakeCardApiClient densityApi() => FakeCardApiClient(
  role: 'manager',
  student: {
    ...desktopStudent,
    'sourceId': 'source-1',
    'customData': {
      'category': 'Взрослые',
      'requestType': 'Новый клиент',
      'lessonType': 'Индивидуальное',
      'level': 'Начальный',
      'learningGoal': 'Для себя',
      'disciplines': ['PIANO', 'VOCAL'],
      'discipline': 'PIANO',
    },
  },
  branches: const [
    {'id': 'branch-1', 'name': 'СОКОЛ'},
  ],
  sources: const [
    {'id': 'source-1', 'displayName': 'Сайт Magic Music', 'isActive': true},
  ],
  customFields: densityFields,
  disciplines: const [
    {'id': 'drums', 'name': 'DRUMS'},
    {'id': 'guitar', 'name': 'GUITAR'},
    {'id': 'piano', 'name': 'PIANO'},
    {'id': 'vocal', 'name': 'VOCAL'},
  ],
  internalNote: const {'body': 'Позвонить перед занятием', 'version': 1},
  operationalHistory: [
    for (var i = 0; i < 10; i++)
      {
        'id': 'history-$i',
        'actionKey': 'crm.student_updated',
        'title': 'Действие $i',
        'occurredAt': DateTime.utc(2026, 9, 22 - i).toIso8601String(),
        'actor': {'name': 'Администратор'},
        'target': {'type': 'student', 'id': 'student-1', 'label': 'Ученик'},
        'changes': [],
      },
  ],
  studentLessonTimelinePage: {
    'items': [
      for (var i = 0; i < 5; i++)
        {
          'id': 'density-$i',
          'version': 1,
          'scheduledAt': DateTime(2026, 9, 23 + i, 15).toIso8601String(),
          'durationMinutes': 60,
          'lifecycleState': 'scheduled',
          'student': {'id': 'student-1', 'name': 'Анна Соколова'},
          'origin': {'kind': 'manual'},
          'settlement': {
            'settlementTypeKey': 'lesson',
            'coveredBySubscription': true,
          },
          'reschedule': {'actionableLessonId': 'density-$i'},
        },
    ],
    'hasPrevious': false,
    'hasNext': false,
  },
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final scale in [1.0, 1.25]) {
    testWidgets('populated desktop shows lesson cells on first screen at $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpClientCard(
        tester,
        api: densityApi(),
        seed: desktopStudent,
        entityType: 'student',
        routed: true,
        capabilitySnapshot: desktopManager,
        textScale: scale,
        topChromeHeight: 64,
        theme: AppTheme.production,
      );
      final profile = find.byKey(const Key('client-desktop-section-profile'));
      expect(tester.getSize(profile).height, lessThan(310));
      final cell = find.byKey(const ValueKey('student-timeline-density-0'));
      expect(
        tester.getBottomRight(cell).dy,
        lessThanOrEqualTo(
          tester
              .getBottomRight(find.byKey(const Key('client-desktop-canvas')))
              .dy,
        ),
        reason:
            'profile=${tester.getRect(profile)}, cell=${tester.getRect(cell)}, '
            'chips=${[
              for (final text in ['DRUMS', 'GUITAR', 'PIANO', 'VOCAL']) tester.getRect(find.widgetWithText(FilterChip, text)),
            ]}',
      );
      expect(cell.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('empty tasks are compact and history starts with three actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpClientCard(
      tester,
      api: densityApi(),
      seed: desktopStudent,
      entityType: 'student',
      routed: true,
      capabilitySnapshot: desktopManager,
      theme: AppTheme.production,
    );
    expect(tester.getSize(find.byType(SharedTasksPanel)).height, lessThan(200));
    expect(find.byType(AuditEventCard), findsNWidgets(3));
    final more = find.byKey(const Key('client-operational-history-more'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.byType(AuditEventCard), findsNWidgets(10));
    final less = find.byKey(const Key('client-operational-history-collapse'));
    await tester.ensureVisible(less);
    await tester.tap(less);
    await tester.pumpAndSettle();
    expect(find.byType(AuditEventCard), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
