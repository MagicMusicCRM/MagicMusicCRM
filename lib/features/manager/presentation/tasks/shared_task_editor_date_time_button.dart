import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SharedTaskDateTimeButton extends StatelessWidget {
  const SharedTaskDateTimeButton({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.canInteract,
    this.dateOnly = false,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool Function() canInteract;
  final bool dateOnly;

  @override
  Widget build(BuildContext context) => ListTile(
    enabled: canInteract(),
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(
      DateFormat(dateOnly ? 'dd.MM.yyyy' : 'dd.MM.yyyy HH:mm').format(value),
    ),
    trailing: const Icon(Icons.calendar_month_outlined),
    onTap: !canInteract()
        ? null
        : () async {
            if (!canInteract()) return;
            final date = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 3650)),
            );
            if (date == null || !context.mounted || !canInteract()) return;
            if (dateOnly) {
              onChanged(DateTime(date.year, date.month, date.day));
              return;
            }
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(value),
            );
            if (time == null || !canInteract()) return;
            onChanged(
              DateTime(date.year, date.month, date.day, time.hour, time.minute),
            );
          },
  );
}
