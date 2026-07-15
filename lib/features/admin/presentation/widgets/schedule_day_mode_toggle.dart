import 'package:flutter/material.dart';
import 'schedule_shared.dart';

/// Segmented toggle between the by-room and by-teacher day layouts. Extracted
/// from _ScheduleWidgetState — pure display; the mode change is applied by the
/// caller (re-fetch happens there because the matrix is grouped server-side).
class ScheduleDayModeToggle extends StatelessWidget {
  final DayViewMode mode;
  final void Function(DayViewMode) onModeChanged;

  const ScheduleDayModeToggle({
    super.key,
    required this.mode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          _toggleButton(
            context,
            'По аудиториям',
            mode == DayViewMode.byRoom,
            () => onModeChanged(DayViewMode.byRoom),
          ),
          const SizedBox(width: 8),
          _toggleButton(
            context,
            'По педагогу',
            mode == DayViewMode.byTeacher,
            () => onModeChanged(DayViewMode.byTeacher),
          ),
        ],
      ),
    );
  }

  Widget _toggleButton(
    BuildContext context,
    String label,
    bool isActive,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.surface
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(80)
                : Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(40),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
