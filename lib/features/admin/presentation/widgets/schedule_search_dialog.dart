import 'package:flutter/material.dart';

/// Search prompt for the schedule (student / teacher / room / date). Returns
/// the entered text, or null on cancel. Extracted from _ScheduleWidgetState.
Future<String?> showScheduleSearchDialog(BuildContext context) async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Поиск в расписании'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Ученик, педагог, аудитория или дата',
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Найти'),
          ),
        ],
      ),
    );
    controller.dispose();
  return query;
}
