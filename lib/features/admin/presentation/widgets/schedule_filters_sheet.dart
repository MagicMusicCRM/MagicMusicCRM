import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_sheet.dart';

import 'schedule_shared.dart';

/// The chosen schedule filters, returned on «Применить» (null on dismiss).
typedef ScheduleFilterResult = ({
  String? branchId,
  DayViewMode mode,
  bool onlyTrial,
  bool onlyConflicts,
  String? teacherId,
});

/// Schedule filters bottom sheet: branch, (in day view) layout mode, and the
/// lesson filters — only trials, only conflicts, a single teacher. Extracted
/// from _ScheduleWidgetState — pure UI; the caller applies the result.
Future<ScheduleFilterResult?> showScheduleFiltersSheet(
  BuildContext context, {
  required String? initialBranchId,
  required DayViewMode initialMode,
  required List<Map<String, dynamic>> branches,
  required bool isDayView,
  required bool initialOnlyTrial,
  required bool initialOnlyConflicts,
  required String? initialTeacherId,
  required List<({String id, String name})> teacherOptions,
}) {
  String? branchId = initialBranchId;
  var dayViewMode = initialMode;
  var onlyTrial = initialOnlyTrial;
  var onlyConflicts = initialOnlyConflicts;
  String? teacherId = initialTeacherId;
  return showMagicSheet<ScheduleFilterResult>(
    context,
    title: 'Фильтры расписания',
    icon: Icons.filter_alt_outlined,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setSheetState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: const Text('Все филиалы'),
              contentPadding: EdgeInsets.zero,
              onTap: () => setSheetState(() => branchId = null),
              trailing: branchId == null
                  ? const Icon(Icons.check_rounded)
                  : null,
            ),
            ...branches.map((branch) {
              final id = branch['id'].toString();
              return ListTile(
                title: Text(branch['name']?.toString() ?? 'Филиал'),
                contentPadding: EdgeInsets.zero,
                onTap: () => setSheetState(() => branchId = id),
                trailing: branchId == id
                    ? const Icon(Icons.check_rounded)
                    : null,
              );
            }),
            const Divider(),
            // Lesson filters.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Только пробные'),
              value: onlyTrial,
              onChanged: (v) => setSheetState(() => onlyTrial = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Только с конфликтами'),
              value: onlyConflicts,
              onChanged: (v) => setSheetState(() => onlyConflicts = v),
            ),
            if (teacherOptions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: DropdownButtonFormField<String?>(
                  initialValue: teacherId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Педагог',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Все педагоги'),
                    ),
                    for (final t in teacherOptions)
                      DropdownMenuItem<String?>(
                        value: t.id,
                        child: Text(t.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setSheetState(() => teacherId = v),
                ),
              ),
            if (isDayView) ...[
              const Divider(),
              ListTile(
                title: const Text('День по аудиториям'),
                contentPadding: EdgeInsets.zero,
                onTap: () =>
                    setSheetState(() => dayViewMode = DayViewMode.byRoom),
                trailing: dayViewMode == DayViewMode.byRoom
                    ? const Icon(Icons.check_rounded)
                    : null,
              ),
              ListTile(
                title: const Text('День по педагогу'),
                contentPadding: EdgeInsets.zero,
                onTap: () =>
                    setSheetState(() => dayViewMode = DayViewMode.byTeacher),
                trailing: dayViewMode == DayViewMode.byTeacher
                    ? const Icon(Icons.check_rounded)
                    : null,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => setSheetState(() {
                    onlyTrial = false;
                    onlyConflicts = false;
                    teacherId = null;
                  }),
                  child: const Text('Сбросить'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop((
                    branchId: branchId,
                    mode: dayViewMode,
                    onlyTrial: onlyTrial,
                    onlyConflicts: onlyConflicts,
                    teacherId: teacherId,
                  )),
                  child: const Text('Применить'),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
