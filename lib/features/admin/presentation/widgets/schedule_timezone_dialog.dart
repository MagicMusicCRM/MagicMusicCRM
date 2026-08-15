import 'package:flutter/material.dart';
import 'schedule_shared.dart';

/// Branch UTC-offset picker dialog. Returns the chosen offset in minutes, or
/// null on cancel. Extracted from _ScheduleWidgetState — pure UI; the caller
/// persists the choice and refetches.
Future<int?> showBranchTimezoneDialog(
  BuildContext context, {
  required String branchName,
  required int currentOffset,
}) {
  // Russia spans UTC+2..UTC+12; offer those (minutes).
  const options = <int>[120, 180, 240, 300, 360, 420, 480, 540, 600, 660, 720];
  var selected = currentOffset;
  if (!options.contains(selected)) selected = 180;

  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('Часовой пояс: $branchName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Время занятий отображается в этом поясе.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              menuMaxHeight: 256,
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Смещение'),
              items: options
                  .map(
                    (m) =>
                        DropdownMenuItem(value: m, child: Text(offsetLabel(m))),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setLocal(() => selected = v);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, selected),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}
