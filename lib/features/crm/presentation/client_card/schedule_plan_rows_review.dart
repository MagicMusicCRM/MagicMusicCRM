import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision_flow.dart';

import 'preferred_schedule_editor.dart';
import 'schedule_plan_constraint_interpreter.dart';

class SchedulePlanRowsReview extends ConsumerStatefulWidget {
  const SchedulePlanRowsReview({
    required this.initialRows,
    required this.branches,
    required this.teachers,
    required this.rooms,
    required this.defaultBranchId,
    required this.decisionCatalogs,
    required this.onValidate,
    this.participantLabels = const {},
    this.submitLabel = 'Проверить и создать',
    super.key,
  });

  final List<PreferredScheduleDraft> initialRows;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> rooms;
  final String? defaultBranchId;
  final Map<String, LessonDecisionCatalog> decisionCatalogs;
  final Map<String, String> participantLabels;
  final String submitLabel;
  final Future<Map<String, dynamic>> Function(List<PreferredScheduleDraft> rows)
  onValidate;

  @override
  ConsumerState<SchedulePlanRowsReview> createState() =>
      _SchedulePlanRowsReviewState();
}

class _SchedulePlanRowsReviewState
    extends ConsumerState<SchedulePlanRowsReview> {
  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  late final List<PreferredScheduleDraft> _rows = List.of(widget.initialRows);
  Map<String, dynamic>? _preview;
  String? _error;
  bool _loading = false;

  Future<void> _edit([int? index]) async {
    final seed = index == null ? _rows.last : _rows[index];
    final result = await showMagicSheet<PreferredScheduleDraft>(
      context,
      title: index == null ? 'Добавить набор дней' : 'Изменить набор дней',
      subtitle: 'Для выбранных дней педагог и аудитория обязательны',
      icon: Icons.edit_calendar_outlined,
      builder: (_) => PreferredScheduleEditor(
        branches: widget.branches,
        teachers: widget.teachers,
        rooms: widget.rooms,
        defaultBranchId: widget.defaultBranchId,
        initialDraft: seed,
        showPeriod: false,
        requireFinancialDecision: true,
        decisionCatalogs: widget.decisionCatalogs,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _rows.add(result);
      } else {
        _rows[index] = result;
      }
      _preview = null;
      _error = null;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _preview = null;
      _error = null;
    });
    try {
      final preview = await widget.onValidate(List.unmodifiable(_rows));
      if (!mounted) return;
      if (preview['valid'] == true) {
        Navigator.pop(context, List<PreferredScheduleDraft>.from(_rows));
        return;
      }
      setState(() => _preview = preview);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userErrorMessage(
            error,
            fallback: 'Не удалось проверить расписание.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final interpreter = SchedulePlanConstraintInterpreter(
      rows: _rows,
      participantLabels: widget.participantLabels,
    );
    final issues = interpreter.issues(_preview);
    final suggestions = interpreter.suggestions(_preview);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < _rows.length; index++) ...[
          _rowCard(index, _rows[index]),
          const SizedBox(height: AppSpace.sm),
        ],
        OutlinedButton.icon(
          key: const Key('schedule-plan-add-row-group'),
          onPressed: _loading ? null : _edit,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Добавить другой набор дней'),
        ),
        if (issues.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          _constraintPanel(issues, suggestions),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpace.md),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _loading ? null : () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: FilledButton(
                key: const Key('schedule-plan-preview-and-create'),
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'Проверяем…' : widget.submitLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _rowCard(int index, PreferredScheduleDraft row) {
    final days = row.weekdays.toList()..sort();
    final teacher = widget.teachers.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id']?.toString() == row.teacherId,
      orElse: () => null,
    );
    final room = widget.rooms.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id']?.toString() == row.roomId,
      orElse: () => null,
    );
    final branch = widget.branches.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id']?.toString() == row.branchId,
      orElse: () => null,
    );
    final teacherName =
        '${teacher?['first_name'] ?? ''} ${teacher?['last_name'] ?? ''}'.trim();
    return Container(
      key: ValueKey('schedule-plan-row-group-$index'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Строка ${index + 1} · ${days.map((day) => _weekdays[day - 1]).join(', ')} · ${row.beginTime}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${teacherName.isEmpty ? 'Педагог не выбран' : teacherName} · '
                  '${room?['name'] ?? 'Аудитория не выбрана'} · '
                  '${branch?['name'] ?? 'Филиал'} · ${row.durationMinutes} мин'
                  '${row.lessonsPerDay > 1 ? ' × ${row.lessonsPerDay}' : ''}',
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('schedule-plan-edit-row-group-$index'),
            onPressed: _loading ? null : () => _edit(index),
            tooltip: 'Изменить строку ${index + 1}',
            icon: const Icon(Icons.edit_outlined),
          ),
          if (_rows.length > 1)
            IconButton(
              key: ValueKey('schedule-plan-delete-row-group-$index'),
              onPressed: _loading
                  ? null
                  : () => setState(() {
                      _rows.removeAt(index);
                      _preview = null;
                    }),
              tooltip: 'Удалить строку ${index + 1}',
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
    );
  }

  Widget _constraintPanel(
    List<SchedulePlanConstraintIssue> issues,
    List<SchedulePlanSuggestion> suggestions,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const Key('schedule-plan-constraint-errors'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.dangerSoft,
        border: Border.all(color: AppColor.danger.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Найдены ограничения расписания',
            style: TextStyle(color: cs.error, fontWeight: FontWeight.w800),
          ),
          Text(
            'Похожие конфликты объединены. Сначала показан ближайший.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpace.sm),
          for (final issue in issues) ...[
            Text(
              '${issue.rowLabel}: ${issue.label} · ${issue.dates.take(3).join(', ')}'
              '${issue.dates.length > 3 ? ' и ещё ${issue.dates.length - 3}' : ''}',
            ),
            if (issue.participantLabels.isNotEmpty)
              Text(
                '${issue.participantLabels.length == 1 ? 'Участник' : 'Участники'}: '
                '${issue.participantLabels.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (issue.rowIndexes.isNotEmpty)
              Text(
                'Пересечение со строками: ${issue.rowIndexes.map((index) => index + 1).join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (issue.lessonIds.isNotEmpty)
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: 2,
                children: [
                  for (final (index, id) in issue.lessonIds.indexed)
                    EntityLinkText(
                      text: 'Открыть занятие ${index + 1}',
                      onPressed: () => openEntityLink(
                        context,
                        ref,
                        EntityLink.typed(
                          entityType: EntityLinkType.lesson,
                          entityId: id,
                        ),
                      ),
                    ),
                ],
              ),
            if (issue.analyzerGrouped)
              Wrap(
                children: [
                  for (final draftIndex in issue.affectedDraftIndexes)
                    TextButton.icon(
                      key: ValueKey(
                        'schedule-plan-fix-group-${issue.fingerprint}-$draftIndex',
                      ),
                      onPressed: _loading ? null : () => _edit(draftIndex),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text('Исправить набор ${draftIndex + 1}'),
                    ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey(
                    'schedule-plan-fix-row-${issue.rowIndex}-${issue.label}-${issue.participantLabel ?? 'all'}',
                  ),
                  onPressed: _loading ? null : () => _edit(issue.draftIndex),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text('Исправить строку ${issue.rowIndex + 1}'),
                ),
              ),
            const SizedBox(height: AppSpace.sm),
          ],
          if (suggestions.isNotEmpty) ...[
            const Divider(),
            const Text(
              'Предлагаемые варианты',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Примените вариант и снова сохраните расписание.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpace.sm),
            for (final item in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: OutlinedButton(
                  key: ValueKey(
                    'schedule-plan-suggestion-${item.previewRowIndex}-${item.suggestion.rank}',
                  ),
                  onPressed: _loading ? null : () => _applySuggestion(item),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      SchedulePlanConstraintInterpreter.suggestionLabel(item),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _applySuggestion(SchedulePlanSuggestion item) {
    final current = _rows[item.draftIndex];
    final offset = item.suggestion.startOffsetMinutes ?? 0;
    setState(() {
      _rows[item.draftIndex] = current.copyWith(
        teacherId: item.suggestion.teacherId,
        roomId: item.suggestion.roomId,
        beginTime: offset == 0
            ? current.beginTime
            : SchedulePlanConstraintInterpreter.offsetTime(
                current.beginTime,
                offset,
              ),
      );
      _preview = null;
      _error = null;
    });
  }
}
