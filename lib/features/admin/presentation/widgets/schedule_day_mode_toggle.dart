import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
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
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<DayViewMode>(
          key: const ValueKey('schedule-day-mode-switcher'),
          segments: const [
            ButtonSegment(
              value: DayViewMode.byRoom,
              icon: Icon(Icons.meeting_room_outlined, size: 17),
              label: Text('По аудиториям'),
            ),
            ButtonSegment(
              value: DayViewMode.byTeacher,
              icon: Icon(Icons.person_outline_rounded, size: 17),
              label: Text('По педагогу'),
            ),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onModeChanged(selection.single),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AppColor.goldSoft
                  : Colors.transparent,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AppColor.gold
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            side: WidgetStatePropertyAll(
              BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withAlpha(48),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
