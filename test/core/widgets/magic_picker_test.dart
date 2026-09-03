import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/magic_picker.dart';

void main() {
  for (final size in [const Size(1200, 900), const Size(390, 844)]) {
    final device = size.width >= 840 ? 'desktop' : 'phone';

    testWidgets('$device date picker keeps locale, year mode and result', (
      tester,
    ) async {
      DateTime? result;
      await _pumpHost(tester, size, (context) async {
        result = await showMagicDatePicker(
          context: context,
          initialDate: DateTime(2025, 9, 16, 14),
          firstDate: DateTime(2024),
          lastDate: DateTime(2027, 12, 31),
          currentDate: DateTime(2026, 9, 3, 12),
          locale: const Locale('ru'),
          initialDatePickerMode: DatePickerMode.year,
          selectableDayPredicate: (date) => date.day != 17,
          helpText: 'Дата занятия',
          confirmText: 'Выбрать дату',
          cancelText: 'Отменить дату',
        );
      });

      await _openPicker(tester);
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.initialDate, DateTime(2025, 9, 16));
      expect(picker.currentDate, DateTime(2026, 9, 3));
      expect(
        Localizations.localeOf(tester.element(find.byType(DatePickerDialog))),
        const Locale('ru'),
      );
      expect(find.byType(YearPicker), findsOneWidget);
      await tester.ensureVisible(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('17'));
      await tester.tap(find.text('Выбрать дату'));
      await tester.pumpAndSettle();
      expect(result, DateTime(2026, 9, 16));

      await _openPicker(tester);
      await tester.tap(find.text('Отменить дату'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$device range picker preserves week and year presets', (
      tester,
    ) async {
      final presets = [
        DateTimeRange(
          start: DateTime(2026, 8, 31, 9),
          end: DateTime(2026, 9, 6, 23, 59),
        ),
        DateTimeRange(
          start: DateTime(2026, 1, 1, 9),
          end: DateTime(2026, 12, 31, 23, 59),
        ),
      ];
      var preset = presets.first;
      DateTimeRange? result;
      await _pumpHost(tester, size, (context) async {
        result = await showMagicDateRangePicker(
          context: context,
          initialDateRange: preset,
          firstDate: DateTime(2020, 1, 1, 12),
          lastDate: DateTime(2035, 12, 31, 12),
          currentDate: DateTime(2026, 9, 3),
          locale: const Locale('ru'),
          helpText: 'Период отчёта',
          saveText: 'Выбрать период',
          cancelText: 'Отменить период',
        );
      });

      for (final value in presets) {
        preset = value;
        await _openPicker(tester);
        final expected = DateUtils.datesOnly(value);
        final picker = tester.widget<DateRangePickerDialog>(
          find.byType(DateRangePickerDialog),
        );
        expect(picker.initialDateRange, expected);
        expect(picker.firstDate, DateTime(2020));
        expect(picker.lastDate, DateTime(2035, 12, 31));
        await tester.tap(find.text('Выбрать период'));
        await tester.pumpAndSettle();
        expect(result, expected);
      }

      await _openPicker(tester);
      final pickerContext = tester.element(find.byType(DateRangePickerDialog));
      final inputModeLabel = MaterialLocalizations.of(
        pickerContext,
      ).inputDateModeButtonLabel;
      await tester.tap(find.byTooltip(inputModeLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отменить период'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(DateRangePickerDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$device time picker retains 24-hour builder and cancel', (
      tester,
    ) async {
      TimeOfDay? result;
      await _pumpHost(tester, size, (context) async {
        result = await showMagicTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 21, minute: 35),
          initialEntryMode: TimePickerEntryMode.input,
          orientation: Orientation.portrait,
          helpText: 'Время занятия',
          confirmText: 'Выбрать время',
          cancelText: 'Отменить время',
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: Localizations.override(
              context: context,
              locale: const Locale('ru'),
              child: child!,
            ),
          ),
        );
      });

      await _openPicker(tester);
      final pickerContext = tester.element(find.byType(TimePickerDialog));
      expect(MediaQuery.alwaysUse24HourFormatOf(pickerContext), isTrue);
      expect(Localizations.localeOf(pickerContext), const Locale('ru'));
      final fields = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(fields.first).controller!.text, '21');
      expect(tester.widget<TextField>(fields.last).controller!.text, '35');
      await tester.enterText(fields.last, '45');
      await tester.tap(find.text('Выбрать время'));
      await tester.pumpAndSettle();
      expect(result, const TimeOfDay(hour: 21, minute: 45));

      await _openPicker(tester);
      await tester.tap(find.text('Отменить время'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpHost(
  WidgetTester tester,
  Size size,
  ValueChanged<BuildContext> open,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        platform: size.width >= 840
            ? TargetPlatform.windows
            : TargetPlatform.android,
      ),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('ru')],
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => open(context),
            child: const Text('Открыть'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openPicker(WidgetTester tester) async {
  final isDesktop =
      Theme.of(tester.element(find.text('Открыть'))).platform ==
      TargetPlatform.windows;
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('magic-dialog-desktop')),
    isDesktop ? findsOneWidget : findsNothing,
  );
  expect(
    find.byKey(const ValueKey('magic-sheet-mobile')),
    isDesktop ? findsNothing : findsOneWidget,
  );
  final expand = find.byKey(const ValueKey('magic-sheet-toggle'));
  if (expand.evaluate().isNotEmpty) {
    await tester.tap(expand);
    await tester.pumpAndSettle();
  }
}
