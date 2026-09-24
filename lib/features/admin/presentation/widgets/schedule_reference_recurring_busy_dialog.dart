import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/widgets/app_dropdown.dart';
import 'package:magic_music_crm/core/widgets/magic_picker.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';

import 'schedule_reference_dialogs.dart';
import 'schedule_reference_models.dart';

Future<Map<String, dynamic>?> showUnavailableRecurringDialog(
  BuildContext context, {
  required String timezone,
  Map<String, dynamic>? initialRule,
}) => showMagicDialog<Map<String, dynamic>>(
  context: context,
  builder: (_) =>
      _RecurringBusyDialog(timezone: timezone, initialRule: initialRule),
);

class _RecurringBusyDialog extends StatefulWidget {
  const _RecurringBusyDialog({required this.timezone, this.initialRule});

  final String timezone;
  final Map<String, dynamic>? initialRule;

  @override
  State<_RecurringBusyDialog> createState() => _RecurringBusyDialogState();
}

class _RecurringBusyDialogState extends State<_RecurringBusyDialog> {
  late int weekday;
  late String start;
  late String end;
  late DateTime validFrom;
  DateTime? validUntil;
  late String reason;

  final dateFormat = DateFormat('dd.MM.yyyy');
  final apiDateFormat = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    final rule = widget.initialRule;
    weekday = (rule?['weekday'] as num?)?.toInt() ?? DateTime.now().weekday;
    start = rule?['localStart']?.toString() ?? '09:00';
    end = rule?['localEnd']?.toString() ?? '18:00';
    validFrom =
        DateTime.tryParse(rule?['validFrom']?.toString() ?? '') ??
        DateUtils.dateOnly(DateTime.now());
    validUntil = DateTime.tryParse(rule?['validUntil']?.toString() ?? '');
    reason = rule?['reason']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initialRule == null
          ? 'Занято каждую неделю'
          : 'Изменить еженедельную занятость',
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
            _dayField(),
            const SizedBox(height: 12),
            _timeFields(),
            if (start.compareTo(end) >= 0)
              const Text('Время окончания должно быть позже начала.'),
            const SizedBox(height: 8),
            _dateFields(),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: reason,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Причина или другое место (необязательно)',
              ),
              onChanged: (value) => reason = value,
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
        onPressed: _canSave ? _submit : null,
        child: Text(widget.initialRule == null ? 'Добавить' : 'Сохранить'),
      ),
    ],
  );

  Widget _dayField() => AppDropdownButtonFormField<int>(
    menuMaxHeight: 256,
    initialValue: weekday,
    decoration: const InputDecoration(labelText: 'День недели'),
    items: [
      for (final day in scheduleReferenceDayNames.entries)
        DropdownMenuItem(value: day.key, child: Text(day.value)),
    ],
    onChanged: (value) {
      if (value != null) setState(() => weekday = value);
    },
  );

  Widget _timeFields() => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      OutlinedButton(onPressed: () => _pickTime(true), child: Text('С $start')),
      OutlinedButton(onPressed: () => _pickTime(false), child: Text('До $end')),
    ],
  );

  Widget _dateFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        onPressed: () => _pickDate(true),
        icon: const Icon(Icons.event_available_outlined),
        label: Text('Начало: ${dateFormat.format(validFrom)}'),
      ),
      OutlinedButton.icon(
        onPressed: () => _pickDate(false),
        icon: const Icon(Icons.event_busy_outlined),
        label: Text(
          validUntil == null
              ? 'Без даты окончания'
              : 'Окончание: ${dateFormat.format(validUntil!)}',
        ),
      ),
      if (validUntil != null)
        TextButton(
          onPressed: () => setState(() => validUntil = null),
          child: const Text('Убрать дату окончания'),
        ),
    ],
  );

  Future<void> _pickTime(bool isStart) async {
    final value = await pickScheduleTime(context, isStart ? start : end);
    if (value == null || !mounted) return;
    setState(() {
      if (isStart) {
        start = value;
      } else {
        end = value;
      }
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final value = await showMagicDatePicker(
      context: context,
      initialDate: isStart ? validFrom : validUntil ?? validFrom,
      firstDate: isStart ? DateTime(2020) : validFrom,
      lastDate: DateTime(2100),
    );
    if (value == null || !mounted) return;
    setState(() {
      if (isStart) {
        validFrom = value;
        if (validUntil != null && validUntil!.isBefore(value)) {
          validUntil = null;
        }
      } else {
        validUntil = value;
      }
    });
  }

  bool get _canSave =>
      start.compareTo(end) < 0 &&
      (validUntil == null || !validUntil!.isBefore(validFrom));

  void _submit() => Navigator.pop(context, {
    'kind': 'recurring',
    'available': false,
    'timezone': widget.timezone,
    'weekday': weekday,
    'localStart': start,
    'localEnd': end,
    'validFrom': apiDateFormat.format(validFrom),
    if (validUntil != null) 'validUntil': apiDateFormat.format(validUntil!),
    if (reason.trim().isNotEmpty) 'reason': reason.trim(),
  });
}
