import 'package:flutter/material.dart';
import 'schedule_shared.dart';

/// Schedule filters bottom sheet: branch selection + (in day view) the layout
/// mode. Returns the chosen (branchId, mode) on «Применить», null on dismiss.
/// Extracted from _ScheduleWidgetState — pure UI; the caller applies the result.
Future<({String? branchId, DayViewMode mode})?> showScheduleFiltersSheet(
  BuildContext context, {
  required String? initialBranchId,
  required DayViewMode initialMode,
  required List<Map<String, dynamic>> branches,
  required bool isDayView,
}) {
  String? branchId = initialBranchId;
  var dayViewMode = initialMode;
  return showModalBottomSheet<({String? branchId, DayViewMode mode})>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => StatefulBuilder(
            builder: (context, setSheetState) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Фильтры расписания',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
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
                      if (isDayView) ...[
                        const Divider(),
                        ListTile(
                          title: const Text('День по аудиториям'),
                          contentPadding: EdgeInsets.zero,
                          onTap: () => setSheetState(
                            () => dayViewMode = DayViewMode.byRoom,
                          ),
                          trailing: dayViewMode == DayViewMode.byRoom
                              ? const Icon(Icons.check_rounded)
                              : null,
                        ),
                        ListTile(
                          title: const Text('День по педагогу'),
                          contentPadding: EdgeInsets.zero,
                          onTap: () => setSheetState(
                            () => dayViewMode = DayViewMode.byTeacher,
                          ),
                          trailing: dayViewMode == DayViewMode.byTeacher
                              ? const Icon(Icons.check_rounded)
                              : null,
                        ),
                      ],
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () => Navigator.of(
                          ctx,
                        ).pop((branchId: branchId, mode: dayViewMode)),
                        child: const Text('Применить'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}
