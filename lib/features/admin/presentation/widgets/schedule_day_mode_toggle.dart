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
              label: Text('По преподавателям'),
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

/// Workspace tabs use the same quiet pill treatment as Leads / Students.
class ScheduleWorkspaceModeTabs extends StatelessWidget {
  const ScheduleWorkspaceModeTabs({
    super.key,
    required this.mode,
    required this.onModeChanged,
  });

  final DayViewMode mode;
  final ValueChanged<DayViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColor.input,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColor.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tab(
                'По аудиториям',
                Icons.meeting_room_outlined,
                DayViewMode.byRoom,
              ),
              _tab(
                'По преподавателям',
                Icons.school_outlined,
                DayViewMode.byTeacher,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _tab(String label, IconData icon, DayViewMode value) {
    final selected = mode == value;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('schedule-workspace-tab-${value.name}'),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () => onModeChanged(value),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.ease,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColor.selectionBg : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? AppColor.selectionBorder : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColor.selectionText : AppColor.text2,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColor.selectionText : AppColor.text2,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
