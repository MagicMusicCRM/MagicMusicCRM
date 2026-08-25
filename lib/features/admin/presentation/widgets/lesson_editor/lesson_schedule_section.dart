import 'dart:async';

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/models/lesson_schedule_analysis.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'lesson_editor_models.dart';

class LessonScheduleSectionModel {
  const LessonScheduleSectionModel({
    required this.draft,
    required this.analysis,
    required this.isAnalyzing,
    required this.minimumDate,
    required this.maximumDate,
    this.errorMessage,
    this.isSaving = false,
  });

  factory LessonScheduleSectionModel.fromEditor({
    required LessonEditorDraft draft,
    required LessonScheduleAnalysis? analysis,
    required bool isAnalyzing,
    required bool isEdit,
    DateTime? now,
    String? errorMessage,
    bool isSaving = false,
  }) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final rollingMinimum = today.subtract(const Duration(days: 30));
    final selectedDate = DateTime(
      draft.localStart.year,
      draft.localStart.month,
      draft.localStart.day,
    );
    return LessonScheduleSectionModel(
      draft: draft,
      analysis: analysis,
      isAnalyzing: isAnalyzing,
      minimumDate: isEdit && selectedDate.isBefore(rollingMinimum)
          ? selectedDate
          : rollingMinimum,
      maximumDate: today.add(const Duration(days: 365)),
      errorMessage: errorMessage,
      isSaving: isSaving,
    );
  }

  final LessonEditorDraft draft;
  final LessonScheduleAnalysis? analysis;
  final bool isAnalyzing;
  final DateTime minimumDate;
  final DateTime maximumDate;
  final String? errorMessage;
  final bool isSaving;
}

class LessonScheduleSection extends StatelessWidget {
  const LessonScheduleSection({
    required this.model,
    required this.onAnalyze,
    required this.onApplySuggestion,
    required this.onOpenConstraint,
    required this.onDateChanged,
    required this.onTimeChanged,
    required this.onDurationChanged,
    super.key,
  });

  final LessonScheduleSectionModel model;
  final FutureOr<void> Function() onAnalyze;
  final FutureOr<void> Function(ScheduleSuggestion value) onApplySuggestion;
  final ValueChanged<LessonConstraintViolation> onOpenConstraint;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<TimeOfDay> onTimeChanged;
  final ValueChanged<int> onDurationChanged;

  @override
  Widget build(BuildContext context) {
    final durationOptions = <int>{
      30,
      45,
      60,
      90,
      120,
      model.draft.durationMinutes,
    }.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ResponsivePair(
          first: _dateButton(context),
          second: _timeButton(context),
        ),
        const SizedBox(height: 16),
        KeyedSubtree(
          key: ValueKey(
            'lesson-duration-selection-${model.draft.durationMinutes}',
          ),
          child: DropdownButtonFormField<int>(
            menuMaxHeight: 256,
            key: const ValueKey('lesson-duration-field'),
            initialValue: model.draft.durationMinutes,
            decoration: const InputDecoration(labelText: 'Длительность *'),
            items: [
              for (final minutes in durationOptions)
                DropdownMenuItem(value: minutes, child: Text('$minutes мин')),
            ],
            onChanged: (value) => onDurationChanged(value ?? 60),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton.icon(
          key: const ValueKey('lesson-run-schedule-analyzer'),
          onPressed: model.isAnalyzing ? null : () => onAnalyze(),
          icon: model.isAnalyzing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.rule_rounded),
          label: Text(
            model.isAnalyzing
                ? 'Проверяем расписание…'
                : 'Проверить конфликты и варианты',
          ),
        ),
        if (!model.isSaving &&
            (model.analysis != null || model.errorMessage != null)) ...[
          const SizedBox(height: AppSpace.md),
          _ScheduleConflictInspector(
            analysis: model.analysis,
            errorMessage: model.errorMessage,
            isAnalyzing: model.isAnalyzing,
            onApplySuggestion: onApplySuggestion,
            onOpenConstraint: onOpenConstraint,
          ),
        ],
      ],
    );
  }

  Widget _dateButton(BuildContext context) {
    final selected = model.draft.localStart;
    final selectedDate = DateTime(selected.year, selected.month, selected.day);
    return OutlinedButton.icon(
      key: const ValueKey('lesson-date-field'),
      onPressed: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: selectedDate.isBefore(model.minimumDate)
              ? model.minimumDate
              : selectedDate,
          firstDate: model.minimumDate,
          lastDate: model.maximumDate,
        );
        if (date != null) onDateChanged(date);
      },
      icon: const Icon(Icons.calendar_today_rounded, size: 18),
      label: Text(_dateLabel(selectedDate)),
    );
  }

  Widget _timeButton(BuildContext context) {
    final selected = TimeOfDay.fromDateTime(model.draft.localStart);
    return OutlinedButton.icon(
      key: const ValueKey('lesson-time-field'),
      onPressed: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: selected,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
        if (time != null) onTimeChanged(time);
      },
      icon: const Icon(Icons.access_time_rounded, size: 18),
      label: Text(selected.format(context)),
    );
  }
}

class _ScheduleConflictInspector extends StatelessWidget {
  const _ScheduleConflictInspector({
    required this.analysis,
    required this.errorMessage,
    required this.isAnalyzing,
    required this.onApplySuggestion,
    required this.onOpenConstraint,
  });

  final LessonScheduleAnalysis? analysis;
  final String? errorMessage;
  final bool isAnalyzing;
  final FutureOr<void> Function(ScheduleSuggestion value) onApplySuggestion;
  final ValueChanged<LessonConstraintViolation> onOpenConstraint;

  @override
  Widget build(BuildContext context) {
    final valid = analysis?.valid == true;
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('lesson-conflict-inspector'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: valid
            ? AppColor.success.withValues(alpha: 0.10)
            : AppColor.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: (valid ? AppColor.success : AppColor.danger).withValues(
            alpha: 0.35,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            valid ? 'Конфликтов нет' : 'Найдены конфликты',
            style: TextStyle(
              color: valid ? AppColor.success : colors.error,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(errorMessage!),
          ],
          for (final violation in analysis?.violations ?? const [])
            _ViolationCard(
              violation: violation,
              onOpenConstraint: onOpenConstraint,
            ),
          if ((analysis?.suggestions ?? const []).isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            const Text(
              'Подходящие варианты',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpace.sm),
            for (final suggestion in analysis!.suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: OutlinedButton(
                  key: ValueKey('lesson-suggestion-${suggestion.rank}'),
                  onPressed: isAnalyzing
                      ? null
                      : () => onApplySuggestion(suggestion),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_suggestionLabel(suggestion)),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ViolationCard extends StatelessWidget {
  const _ViolationCard({
    required this.violation,
    required this.onOpenConstraint,
  });

  final LessonConstraintViolation violation;
  final ValueChanged<LessonConstraintViolation> onOpenConstraint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColor.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.danger.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            violation.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(violation.resourceLabel, style: const TextStyle(fontSize: 12)),
          if (violation.conflictingLessonIds.isNotEmpty)
            Wrap(
              spacing: 4,
              children: [
                for (final (index, lessonId)
                    in violation.conflictingLessonIds.indexed)
                  EntityLinkText(
                    key: ValueKey('conflict-lesson-$lessonId'),
                    onPressed: () => onOpenConstraint(violation),
                    text: 'Открыть занятие ${index + 1}',
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

String _dateLabel(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.'
    '${value.month.toString().padLeft(2, '0')}.${value.year}';

String _suggestionLabel(ScheduleSuggestion suggestion) {
  final details = <String>[
    if (suggestion.roomName != null) suggestion.roomName!,
    if (suggestion.teacherName != null) suggestion.teacherName!,
    if (suggestion.startAt != null)
      '${_dateLabel(suggestion.startAt!).substring(0, 5)} · '
          '${suggestion.startAt!.hour.toString().padLeft(2, '0')}:'
          '${suggestion.startAt!.minute.toString().padLeft(2, '0')}',
  ];
  return '№${suggestion.rank} · ${suggestion.title}'
      '${details.isEmpty ? '' : ' · ${details.join(' · ')}'}';
}
