import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_models.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_rate_dialogs.dart';

Widget _host({
  required num? currentRate,
  required ValueChanged<TeacherStatsGroupRateChange?> onResult,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            onResult(
              await showTeacherStatsGroupRateDialog(
                context: context,
                groupName: 'Группа А',
                currentRate: currentRate,
              ),
            );
          },
          child: const Text('Открыть'),
        ),
      ),
    ),
  );
}

void main() {
  for (final testCase in <({String name, num? rate})>[
    (name: 'numeric zero', rate: 0),
    (name: 'inherited null', rate: null),
  ]) {
    testWidgets('group rate dialog opens and preserves ${testCase.name}', (
      tester,
    ) async {
      TeacherStatsGroupRateChange? result;
      await tester.pumpWidget(
        _host(currentRate: testCase.rate, onResult: (value) => result = value),
      );

      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      expect(find.text('Группа А'), findsOneWidget);

      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.teacherRate, testCase.rate);
    });
  }
}
