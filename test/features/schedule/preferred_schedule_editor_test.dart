import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/preferred_schedule_editor.dart';

const _branches = [
  {'id': 'branch-a', 'name': 'Сокол'},
  {'id': 'branch-b', 'name': 'Центр'},
];
const _teachers = [
  {
    'id': 'teacher-a',
    'first_name': 'Мария',
    'last_name': 'Иванова',
    'status': 'active',
    'assigned_branches': [
      {'id': 'branch-a', 'name': 'Сокол'},
    ],
  },
];
const _rooms = [
  {'id': 'room-a', 'branch_id': 'branch-a', 'name': 'Класс 1'},
  {'id': 'room-b', 'branch_id': 'branch-b', 'name': 'Класс 2'},
];

void main() {
  for (final width in const [360.0, 840.0]) {
    testWidgets('editor uses client branch and fits ${width.toInt()}', (
      tester,
    ) async {
      await _openEditor(tester, width: width);

      expect(find.text('Сокол'), findsOneWidget);
      expect(find.text('Вся школа'), findsNothing);
      expect(find.text('Дни недели'), findsOneWidget);
      expect(find.text('Занятий в день'), findsOneWidget);
      expect(find.text('Дата начала'), findsOneWidget);
      expect(find.text('Дата окончания'), findsOneWidget);
      expect(find.text('Описание'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('validation keeps an incomplete preference open', (tester) async {
    await _openEditor(tester, width: 840);

    await tester.ensureVisible(
      find.byKey(const ValueKey('preferred-schedule-save')),
    );
    await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
    await tester.pumpAndSettle();

    expect(find.text('Выберите педагога.'), findsOneWidget);
    expect(find.byKey(const ValueKey('magic-sheet-frame')), findsOneWidget);
  });

  testWidgets('system Back protects dirty preference input', (tester) async {
    await _openEditor(tester, width: 360);
    await tester.tap(find.byKey(const ValueKey('magic-sheet-toggle')));
    await tester.pumpAndSettle();
    final notes = find.byKey(const ValueKey('preferred-schedule-notes'));
    await tester.ensureVisible(notes);
    await tester.enterText(notes, 'Только после школы');
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Сохранить изменения?'), findsOneWidget);
    await tester.tap(find.text('Остаться'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('magic-sheet-frame')), findsOneWidget);
    expect(find.text('Только после школы'), findsOneWidget);
  });

  testWidgets('editor returns weekdays and consecutive lessons per day', (
    tester,
  ) async {
    PreferredScheduleDraft? result;
    await _openEditor(tester, width: 840, onResult: (value) => result = value);

    final monday = find.byKey(const ValueKey('preferred-schedule-weekday-1'));
    if (!tester.widget<FilterChip>(monday).selected) {
      await tester.tap(monday);
    }
    await _choose(
      tester,
      const ValueKey('preferred-schedule-teacher'),
      'Мария Иванова',
    );
    await _choose(tester, const ValueKey('preferred-schedule-room'), 'Класс 1');

    await tester.tap(
      find.byKey(const ValueKey('preferred-schedule-lessons-per-day')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('preferred-schedule-save')),
    );
    await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.branchId, 'branch-a');
    expect(result!.teacherId, 'teacher-a');
    expect(result!.roomId, 'room-a');
    expect(result!.weekdays, contains(DateTime.monday));
    expect(result!.lessonsPerDay, 2);
  });
}

Future<void> _choose(WidgetTester tester, Key field, String option) async {
  await tester.tap(find.byKey(field));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(Scrollbar).last,
      matching: find.text(option),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openEditor(
  WidgetTester tester, {
  required double width,
  ValueChanged<PreferredScheduleDraft?>? onResult,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                final result = await showMagicSheet<PreferredScheduleDraft>(
                  context,
                  title: 'Добавить предпочтение',
                  builder: (_) => const PreferredScheduleEditor(
                    branches: _branches,
                    teachers: _teachers,
                    rooms: _rooms,
                    defaultBranchId: 'branch-a',
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
}
