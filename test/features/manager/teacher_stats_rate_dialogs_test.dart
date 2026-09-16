import 'package:magic_music_crm/core/widgets/app_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
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
  testWidgets('rate correction validates reason and accepts inherited rate', (
    tester,
  ) async {
    TeacherStatsRateChange? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.production,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showTeacherStatsRateDialog(
                  context: context,
                  title: 'Изменить расчёт',
                  description: 'Выбранное занятие',
                  lessonIds: ['lesson'],
                  initialRate: 900,
                );
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppDropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ставка педагога (по умолчанию)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Укажите причину изменения ставки'), findsOneWidget);
    final reasonDecoration = tester.widget<InputDecorator>(
      find.byWidgetPredicate(
        (widget) =>
            widget is InputDecorator &&
            widget.decoration.labelText == 'Причина изменения *',
      ),
    );
    expect(
      reasonDecoration.decoration.errorText,
      'Укажите причину изменения ставки',
    );
    expect(
      reasonDecoration.decoration.errorBorder!.borderSide.color,
      AppColor.danger,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Причина изменения *'),
      '   ',
    );
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Причина изменения *'),
      'Вернуть стандартную ставку',
    );
    await tester.pumpAndSettle();
    expect(find.text('Укажите причину изменения ставки'), findsNothing);
    tester
        .widget<AppDropdownButtonFormField<String>>(
          find.byType(AppDropdownButtonFormField<String>),
        )
        .onChanged!('custom');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Введите ставку'), findsOneWidget);
    tester
        .widget<AppDropdownButtonFormField<String>>(
          find.byType(AppDropdownButtonFormField<String>),
        )
        .onChanged!('inherit');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.teacherRate, isNull);
  });

  testWidgets('empty custom group rate cannot silently clear the override', (
    tester,
  ) async {
    TeacherStatsGroupRateChange? result;
    await tester.pumpWidget(
      _host(currentRate: 900, onResult: (value) => result = value),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    tester
        .widget<AppDropdownButtonFormField<String>>(
          find.byType(AppDropdownButtonFormField<String>),
        )
        .onChanged!('custom');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Введите ставку'), findsOneWidget);
  });
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
