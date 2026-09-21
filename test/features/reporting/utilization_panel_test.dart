import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/utilization_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/utilization_panel.dart';

void main() {
  testWidgets('utilization separates plan/fact and reports missing windows', (
    tester,
  ) async {
    EntityLink? opened;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          utilizationDataSourceProvider.overrideWithValue(
            _FakeUtilizationDataSource(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: UtilizationPanel(
              filter: DashboardFilter(
                from: DateTime(2026, 9, 1),
                to: DateTime(2026, 9, 30),
              ),
              onOpenEntity: (link) => opened = link,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('План: 50%'), findsOneWidget);
    expect(find.text('Факт: 25%'), findsOneWidget);
    expect(find.textContaining('Посещений: 5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('utilization-open-teacher-1')));
    expect(opened?.rawEntityType, 'teacher');

    await tester.tap(find.text('Помещения'));
    await tester.pumpAndSettle();
    expect(find.text('Нет данных'), findsWidgets);
  });
}

class _FakeUtilizationDataSource implements UtilizationDataSource {
  @override
  Future<Map<String, dynamic>> load(DashboardFilter filter) async => {
    'teachers': [
      {
        'id': 'teacher-1',
        'name': 'Мария Петрова',
        'kind': 'teacher',
        'availableMinutes': 600,
        'plannedMinutes': 300,
        'actualMinutes': 150,
        'plannedUtilization': 0.5,
        'actualUtilization': 0.25,
        'plannedLessons': 4,
        'actualLessons': 2,
        'attendances': 5,
        'entityLink': {'entityType': 'teacher', 'entityId': 'teacher-1'},
      },
    ],
    'rooms': [
      {
        'id': 'room-1',
        'name': 'Класс 1',
        'kind': 'room',
        'availableMinutes': 0,
        'plannedMinutes': 0,
        'actualMinutes': 0,
        'plannedUtilization': null,
        'actualUtilization': null,
        'plannedLessons': 0,
        'actualLessons': 0,
        'attendances': 0,
        'entityLink': {'entityType': 'room', 'entityId': 'room-1'},
      },
    ],
  };
}
