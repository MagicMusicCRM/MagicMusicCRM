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
