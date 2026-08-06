import 'package:flutter/material.dart';

/// Search prompt for the schedule (student / teacher / room / date). Returns
/// the entered text, or null on cancel. Extracted from _ScheduleWidgetState.
Future<String?> showScheduleSearchDialog(
  BuildContext context, {
  String initialValue = '',
}) async {
  var value = initialValue;
  final query = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Поиск в расписании'),
      content: TextFormField(
        initialValue: initialValue,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Ученик, педагог, аудитория или дата',
        ),
        onChanged: (next) => value = next,
        onFieldSubmitted: (next) => Navigator.of(ctx).pop(next),
      ),
      actions: [
        if (initialValue.trim().isNotEmpty)
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(''),
            child: const Text('Очистить'),
          ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(value),
          child: const Text('Найти'),
        ),
      ],
    ),
  );
  return query;
}
