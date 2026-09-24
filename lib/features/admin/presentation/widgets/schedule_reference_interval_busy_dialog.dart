import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/widgets/magic_picker.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';

import 'schedule_reference_dialogs.dart';
import 'schedule_reference_timezone.dart';

Future<Map<String, dynamic>?> showUnavailableIntervalDialog(
  BuildContext context, {
  required String timezone,
  Map<String, dynamic>? initialRule,
}) => showMagicDialog<Map<String, dynamic>>(
  context: context,
  builder: (_) =>
      _IntervalBusyDialog(timezone: timezone, initialRule: initialRule),
);

class _IntervalBusyDialog extends StatefulWidget {
  const _IntervalBusyDialog({required this.timezone, this.initialRule});

  final String timezone;
  final Map<String, dynamic>? initialRule;

  @override
  State<_IntervalBusyDialog> createState() => _IntervalBusyDialogState();
}

class _IntervalBusyDialogState extends State<_IntervalBusyDialog> {
  late DateTime startDate;
  late DateTime endDate;
  late String startTime;
  late String endTime;
  late String reason;

  final dateFormat = DateFormat('dd.MM.yyyy');

  @override
  void initState() {
    super.initState();
    final now = DateUtils.dateOnly(DateTime.now());
    final startUtc = DateTime.tryParse(
      widget.initialRule?['startsAt']?.toString() ?? '',
    );
    final endUtc = DateTime.tryParse(
      widget.initialRule?['endsAt']?.toString() ?? '',
    );
    final startLocal = startUtc == null
        ? null
        : scheduleUtcToLocal(startUtc, widget.timezone);
    final endLocal = endUtc == null
        ? null
        : scheduleUtcToLocal(endUtc, widget.timezone);
    startDate = startLocal ?? now;
    endDate = endLocal ?? startDate;
    startTime = startLocal == null ? '09:00' : _timeText(startLocal);
    endTime = endLocal == null ? '18:00' : _timeText(endLocal);
    reason = widget.initialRule?['reason']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initialRule == null ? 'Занято на дату' : 'Изменить занятый период',
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Время: ${widget.timezone}'),
            const SizedBox(height: 12),
            _dateButton(isStart: true),
            _timeButton(isStart: true),
            const SizedBox(height: 8),
            _dateButton(isStart: false),
            _timeButton(isStart: false),
            if (_bounds == null)
              const Text(
                'Окончание должно быть позже начала. Проверьте даты и время.',
              ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: reason,
              maxLength: 300,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Причина или другое место *',
              ),
              onChanged: (value) => setState(() => reason = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: reason.trim().isEmpty || _bounds == null ? null : _submit,
        child: Text(widget.initialRule == null ? 'Добавить' : 'Сохранить'),
      ),
    ],
  );

  Widget _dateButton({required bool isStart}) => OutlinedButton.icon(
    onPressed: () => _pickDate(isStart),
    icon: const Icon(Icons.event_outlined),
    label: Text(
      '${isStart ? 'Начало' : 'Окончание'}: '
      '${dateFormat.format(isStart ? startDate : endDate)}',
    ),
  );

  Widget _timeButton({required bool isStart}) => OutlinedButton.icon(
    onPressed: () => _pickTime(isStart),
    icon: const Icon(Icons.schedule_outlined),
    label: Text('Время: ${isStart ? startTime : endTime}'),
  );

  Future<void> _pickDate(bool isStart) async {
    final value = await showMagicDatePicker(
      context: context,
      initialDate: isStart ? startDate : endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value == null || !mounted) return;
    setState(() {
      if (isStart) {
        startDate = value;
        if (endDate.isBefore(value)) endDate = value;
      } else {
        endDate = value;
      }
    });
  }

  Future<void> _pickTime(bool isStart) async {
    final value = await pickScheduleTime(
      context,
      isStart ? startTime : endTime,
    );
    if (value == null || !mounted) return;
    setState(() {
      if (isStart) {
        startTime = value;
      } else {
        endTime = value;
      }
    });
  }

  (DateTime, DateTime)? get _bounds {
    try {
      final start = scheduleLocalToUtc(startDate, startTime, widget.timezone);
      final end = scheduleLocalToUtc(endDate, endTime, widget.timezone);
      return end.isAfter(start) ? (start, end) : null;
    } on ArgumentError {
      return null;
    }
  }

  void _submit() {
    final bounds = _bounds;
    if (bounds == null) return;
    Navigator.pop(context, {
      'kind': 'interval',
      'available': false,
      'timezone': widget.timezone,
      'startsAt': bounds.$1.toIso8601String(),
      'endsAt': bounds.$2.toIso8601String(),
      'reason': reason.trim(),
    });
  }

  String _timeText(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
