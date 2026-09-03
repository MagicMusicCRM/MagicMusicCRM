import 'package:magic_music_crm/core/widgets/magic_picker.dart';
import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:intl/intl.dart';

Future<String?> pickScheduleTime(BuildContext context, String current) async {
  final parts = current.split(':').map(int.tryParse).toList();
  final picked = await showMagicTimePicker(
    context: context,
    initialTime: TimeOfDay(
      hour: parts.firstOrNull ?? 9,
      minute: parts.elementAtOrNull(1) ?? 0,
    ),
  );
  return picked == null
      ? null
      : '${picked.hour.toString().padLeft(2, '0')}:'
            '${picked.minute.toString().padLeft(2, '0')}';
}

Future<Map<String, dynamic>?> showBranchExceptionDialog(
  BuildContext context,
) async {
  final now = DateTime.now();
  final date = await showMagicDatePicker(
    context: context,
    firstDate: now.subtract(const Duration(days: 365)),
    lastDate: now.add(const Duration(days: 730)),
    initialDate: now,
  );
  if (date == null || !context.mounted) return null;
  final closed = await showMagicDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Исключение'),
      content: const Text('Филиал закрыт весь день?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Особые часы'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Закрыт'),
        ),
      ],
    ),
  );
  if (closed == null || !context.mounted) return null;
  final times = await _branchExceptionTimes(context, closed);
  if (times == null) return null;
  return {
    'date': DateFormat('yyyy-MM-dd').format(date),
    'closed': closed,
    'open': times.$1,
    'close': times.$2,
  };
}

Future<(String?, String?)?> _branchExceptionTimes(
  BuildContext context,
  bool closed,
) async {
  if (closed) return (null, null);
  final open = await pickScheduleTime(context, '09:00');
  if (open == null || !context.mounted) return null;
  final close = await pickScheduleTime(context, '21:00');
  return close == null ? null : (open, close);
}

Future<Map<String, dynamic>?> showUnavailableIntervalDialog(
  BuildContext context,
) async {
  final now = DateTime.now();
  final date = await showMagicDatePicker(
    context: context,
    firstDate: now.subtract(const Duration(days: 30)),
    lastDate: now.add(const Duration(days: 730)),
    initialDate: now,
  );
  if (date == null || !context.mounted) return null;
  final startText = await pickScheduleTime(context, '09:00');
  if (startText == null || !context.mounted) return null;
  final endText = await pickScheduleTime(context, '18:00');
  if (endText == null || !context.mounted) return null;
  final reason = await _showUnavailableReasonDialog(context);
  if (reason == null) return null;
  return {
    'kind': 'interval',
    'available': false,
    'startsAt': _combineUtc(date, startText).toIso8601String(),
    'endsAt': _combineUtc(date, endText).toIso8601String(),
    'reason': reason,
  };
}

Future<String?> _showUnavailableReasonDialog(BuildContext context) {
  var reasonText = '';
  return showMagicDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Причина недоступности'),
        content: TextField(
          autofocus: true,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Причина недоступности *',
            hintText: 'Будет видна сотрудникам в настройках расписания',
          ),
          onChanged: (value) => setDialogState(() => reasonText = value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: reasonText.trim().isEmpty
                ? null
                : () => Navigator.pop(context, reasonText.trim()),
            child: const Text('Добавить'),
          ),
        ],
      ),
    ),
  );
}

DateTime _combineUtc(DateTime date, String time) {
  final parts = time.split(':').map(int.parse).toList();
  return DateTime(date.year, date.month, date.day, parts[0], parts[1]).toUtc();
}
