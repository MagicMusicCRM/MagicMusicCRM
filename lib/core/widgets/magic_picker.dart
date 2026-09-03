import 'package:flutter/material.dart';

import 'magic_sheet.dart';

/// Opens Flutter's date picker through the shared adaptive modal route.
Future<DateTime?> showMagicDatePicker({
  required BuildContext context,
  DateTime? initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? currentDate,
  DatePickerEntryMode initialEntryMode = DatePickerEntryMode.calendar,
  DatePickerMode initialDatePickerMode = DatePickerMode.day,
  SelectableDayPredicate? selectableDayPredicate,
  String? helpText,
  String? cancelText,
  String? confirmText,
  Locale? locale,
  TransitionBuilder? builder,
}) => _showMagicPicker<DateTime>(
  context: context,
  locale: locale ?? DatePickerTheme.of(context).locale,
  builder: builder,
  picker: DatePickerDialog(
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    currentDate: currentDate,
    initialEntryMode: initialEntryMode,
    initialCalendarMode: initialDatePickerMode,
    selectableDayPredicate: selectableDayPredicate,
    helpText: helpText,
    cancelText: cancelText,
    confirmText: confirmText,
  ),
);

/// Keeps Flutter's inclusive range selection and input validation unchanged.
Future<DateTimeRange?> showMagicDateRangePicker({
  required BuildContext context,
  DateTimeRange? initialDateRange,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? currentDate,
  DatePickerEntryMode initialEntryMode = DatePickerEntryMode.calendar,
  String? helpText,
  String? cancelText,
  String? confirmText,
  String? saveText,
  Locale? locale,
  TransitionBuilder? builder,
}) {
  initialDateRange = initialDateRange == null
      ? null
      : DateUtils.datesOnly(initialDateRange);
  firstDate = DateUtils.dateOnly(firstDate);
  lastDate = DateUtils.dateOnly(lastDate);
  assert(!lastDate.isBefore(firstDate));
  assert(
    initialDateRange == null ||
        (!initialDateRange.start.isBefore(firstDate) &&
            !initialDateRange.end.isAfter(lastDate)),
    'The initial range must be within firstDate and lastDate.',
  );

  return _showMagicPicker<DateTimeRange>(
    context: context,
    locale: locale,
    builder: builder,
    picker: DateRangePickerDialog(
      initialDateRange: initialDateRange,
      firstDate: firstDate,
      lastDate: lastDate,
      currentDate: currentDate,
      initialEntryMode: initialEntryMode,
      helpText: helpText,
      cancelText: cancelText,
      confirmText: confirmText,
      saveText: saveText,
    ),
  );
}

/// Preserves the caller's builder, including lesson editors' 24-hour format.
Future<TimeOfDay?> showMagicTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  TransitionBuilder? builder,
  TimePickerEntryMode initialEntryMode = TimePickerEntryMode.dial,
  String? cancelText,
  String? confirmText,
  String? helpText,
  Orientation? orientation,
}) => _showMagicPicker<TimeOfDay>(
  context: context,
  builder: builder,
  picker: TimePickerDialog(
    initialTime: initialTime,
    initialEntryMode: initialEntryMode,
    cancelText: cancelText,
    confirmText: confirmText,
    helpText: helpText,
    orientation: orientation,
  ),
);

Future<T?> _showMagicPicker<T>({
  required BuildContext context,
  required Widget picker,
  TransitionBuilder? builder,
  Locale? locale,
}) {
  assert(debugCheckHasMaterialLocalizations(context));
  if (locale != null) {
    picker = Localizations.override(
      context: context,
      locale: locale,
      child: picker,
    );
  }
  return showMagicDialog<T>(
    context: context,
    builder: (context) => builder == null ? picker : builder(context, picker),
  );
}
