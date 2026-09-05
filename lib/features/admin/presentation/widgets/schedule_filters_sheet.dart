import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';

import 'schedule_shared.dart';

/// The chosen schedule filters, returned on «Применить» (null on dismiss).
typedef ScheduleFilterResult = ({
  String? branchId,
  DayViewMode mode,
  bool onlyTrial,
  bool onlyConflicts,
  String? teacherId,
});

const _allBranches = '__all_branches__';
const _allTeachers = '__all_teachers__';
const _allLessons = '__all_lessons__';
const _onlyTrialLessons = '__only_trial_lessons__';
const _allConflictStates = '__all_conflict_states__';
const _onlyConflictedLessons = '__only_conflicted_lessons__';

/// Reusable schedule filter form. Desktop mounts it inline as a collapsible
/// panel; compact layouts keep the same form inside the canonical bottom sheet.
/// Every existing filter is represented by a labelled dropdown so the active
/// scope is visible before the user applies it.
class ScheduleFiltersPanel extends StatefulWidget {
  const ScheduleFiltersPanel({
    super.key,
    required this.initialBranchId,
    required this.initialMode,
    required this.branches,
    required this.isDayView,
    required this.initialOnlyTrial,
    required this.initialOnlyConflicts,
    required this.initialTeacherId,
    required this.teacherOptions,
    required this.onApply,
    this.showHeader = false,
  });

  final String? initialBranchId;
  final DayViewMode initialMode;
  final List<Map<String, dynamic>> branches;
  final bool isDayView;
  final bool initialOnlyTrial;
  final bool initialOnlyConflicts;
  final String? initialTeacherId;
  final List<({String id, String name})> teacherOptions;
  final ValueChanged<ScheduleFilterResult> onApply;
  final bool showHeader;

  @override
  State<ScheduleFiltersPanel> createState() => _ScheduleFiltersPanelState();
}

class _ScheduleFiltersPanelState extends State<ScheduleFiltersPanel> {
  late String? _branchId;
  late DayViewMode _mode;
  late bool _onlyTrial;
  late bool _onlyConflicts;
  late String? _teacherId;

  @override
  void initState() {
    super.initState();
    _restoreInitialValues();
  }

  @override
  void didUpdateWidget(covariant ScheduleFiltersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialBranchId != widget.initialBranchId ||
        oldWidget.initialMode != widget.initialMode ||
        oldWidget.initialOnlyTrial != widget.initialOnlyTrial ||
        oldWidget.initialOnlyConflicts != widget.initialOnlyConflicts ||
        oldWidget.initialTeacherId != widget.initialTeacherId) {
      _restoreInitialValues();
    }
  }

  void _restoreInitialValues() {
    _branchId = widget.initialBranchId;
    _mode = widget.initialMode;
    _onlyTrial = widget.initialOnlyTrial;
    _onlyConflicts = widget.initialOnlyConflicts;
    _teacherId = widget.initialTeacherId;
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 18),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpace.md,
      vertical: AppSpace.md,
    ),
  );

  Widget _dropdown({
    required Key key,
    required String label,
    required IconData icon,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return KeyedSubtree(
      key: key,
      child: DropdownButtonFormField<String>(
        menuMaxHeight: 256,
        key: ValueKey('$label-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: _decoration(label, icon),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  void _resetAdditionalFilters() {
    setState(() {
      _teacherId = null;
      _onlyTrial = false;
      _onlyConflicts = false;
    });
  }

  void _apply() {
    widget.onApply((
      branchId: _branchId,
      mode: _mode,
      onlyTrial: _onlyTrial,
      onlyConflicts: _onlyConflicts,
      teacherId: _teacherId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 960
            ? 3
            : constraints.maxWidth >= 580
            ? 2
            : 1;
        final fieldWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - AppSpace.md * (columns - 1)) / columns;
        final fields = <Widget>[
          _dropdown(
            key: const ValueKey('schedule-filter-branch'),
            label: 'Филиал',
            icon: Icons.location_on_outlined,
            value: _branchId ?? _allBranches,
            items: [
              const DropdownMenuItem(
                value: _allBranches,
                child: Text('Все филиалы'),
              ),
              for (final branch in widget.branches)
                DropdownMenuItem(
                  value: branch['id']?.toString(),
                  child: Text(
                    branch['name']?.toString() ?? 'Филиал',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(
              () => _branchId = value == _allBranches ? null : value,
            ),
          ),
          _dropdown(
            key: const ValueKey('schedule-filter-teacher'),
            label: 'Преподаватель',
            icon: Icons.school_outlined,
            value: _teacherId ?? _allTeachers,
            items: [
              const DropdownMenuItem(
                value: _allTeachers,
                child: Text('Все преподаватели'),
              ),
              for (final teacher in widget.teacherOptions)
                DropdownMenuItem(
                  value: teacher.id,
                  child: Text(
                    teacher.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(
              () => _teacherId = value == _allTeachers ? null : value,
            ),
          ),
          _dropdown(
            key: const ValueKey('schedule-filter-lesson-type'),
            label: 'Тип занятий',
            icon: Icons.auto_awesome_outlined,
            value: _onlyTrial ? _onlyTrialLessons : _allLessons,
            items: const [
              DropdownMenuItem(value: _allLessons, child: Text('Все занятия')),
              DropdownMenuItem(
                value: _onlyTrialLessons,
                child: Text('Только пробные'),
              ),
            ],
            onChanged: (value) =>
                setState(() => _onlyTrial = value == _onlyTrialLessons),
          ),
          _dropdown(
            key: const ValueKey('schedule-filter-conflicts'),
            label: 'Конфликты',
            icon: Icons.warning_amber_rounded,
            value: _onlyConflicts ? _onlyConflictedLessons : _allConflictStates,
            items: const [
              DropdownMenuItem(
                value: _allConflictStates,
                child: Text('Все состояния'),
              ),
              DropdownMenuItem(
                value: _onlyConflictedLessons,
                child: Text('Только с конфликтами'),
              ),
            ],
            onChanged: (value) => setState(
              () => _onlyConflicts = value == _onlyConflictedLessons,
            ),
          ),
          if (widget.isDayView)
            _dropdown(
              key: const ValueKey('schedule-filter-grouping'),
              label: 'Группировка',
              icon: Icons.view_timeline_outlined,
              value: _mode.name,
              items: const [
                DropdownMenuItem(value: 'byRoom', child: Text('По аудиториям')),
                DropdownMenuItem(
                  value: 'byTeacher',
                  child: Text('По преподавателям'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _mode = DayViewMode.values.byName(value));
              },
            ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showHeader) ...[
              Row(
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: AppColor.gold,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      'Параметры отображения',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
            ],
            Wrap(
              spacing: AppSpace.md,
              runSpacing: AppSpace.md,
              children: [
                for (final field in fields)
                  SizedBox(width: fieldWidth, child: field),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                TextButton.icon(
                  onPressed: _resetAdditionalFilters,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Сбросить'),
                ),
                FilledButton.icon(
                  key: const ValueKey('schedule-filter-apply'),
                  onPressed: _apply,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Применить'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColor.gold,
                    foregroundColor: AppColor.onGold,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Compact schedule filters bottom sheet. The caller applies the returned
/// result; desktop renders [ScheduleFiltersPanel] inline instead.
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
  return showMagicSheet<ScheduleFilterResult>(
    context,
    title: 'Фильтры расписания',
    icon: Icons.filter_alt_outlined,
    builder: (ctx) => ScheduleFiltersPanel(
      initialBranchId: initialBranchId,
      initialMode: initialMode,
      branches: branches,
      isDayView: isDayView,
      initialOnlyTrial: initialOnlyTrial,
      initialOnlyConflicts: initialOnlyConflicts,
      initialTeacherId: initialTeacherId,
      teacherOptions: teacherOptions,
      onApply: (result) => Navigator.of(ctx).pop(result),
    ),
  );
}
