import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'preferred_schedule_draft.dart';
import 'schedule_plan_constraint_interpreter.dart';

typedef SchedulePlanDraftEditor =
    Future<PreferredScheduleDraft?> Function(
      BuildContext context,
      PreferredScheduleDraft seed,
      bool adding,
    );

typedef SchedulePlanDraftSummary = String Function(PreferredScheduleDraft row);

typedef SchedulePlanRowsReviewResult = ({
  List<PreferredScheduleDraft> rows,
  String? historyPreviewToken,
});

class SchedulePlanRowsReview extends ConsumerStatefulWidget {
  const SchedulePlanRowsReview({
    required this.initialRows,
    required this.onEditDraft,
    required this.rowSummary,
    required this.onValidate,
    this.participantLabels = const {},
    this.submitLabel = 'Проверить и создать',
    super.key,
  });

  final List<PreferredScheduleDraft> initialRows;
  final SchedulePlanDraftEditor onEditDraft;
  final SchedulePlanDraftSummary rowSummary;
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

  Map<String, dynamic>? get _historical {
    final value = _preview?['historical'];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  bool get _awaitingHistoryConfirmation =>
      _preview?['valid'] == true &&
      _historical?['confirmRequired'] == true &&
      _historical?['previewToken']?.toString().isNotEmpty == true;

  Future<void> _edit([int? index]) async {
    final seed = index == null ? _rows.last : _rows[index];
    final result = await widget.onEditDraft(context, seed, index == null);
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
    if (_awaitingHistoryConfirmation) {
      Navigator.pop(context, (
        rows: List<PreferredScheduleDraft>.from(_rows),
        historyPreviewToken: _historical!['previewToken'].toString(),
      ));
      return;
    }
    setState(() {
      _loading = true;
      _preview = null;
      _error = null;
    });
    try {
      final preview = await widget.onValidate(List.unmodifiable(_rows));
      if (!mounted) return;
      if (preview['valid'] == true) {
        final historical = preview['historical'];
        if (historical is Map && historical['confirmRequired'] == true) {
          setState(() => _preview = preview);
          return;
        }
        Navigator.pop(context, (
          rows: List<PreferredScheduleDraft>.from(_rows),
          historyPreviewToken: null,
        ));
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
        if (_awaitingHistoryConfirmation) ...[
          const SizedBox(height: AppSpace.md),
          _historyReview(),
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
                child: Text(
                  _loading
                      ? 'Проверяем…'
                      : _awaitingHistoryConfirmation
                      ? (widget.submitLabel.contains('создать')
                            ? 'Подтвердить и создать'
                            : 'Подтвердить и сохранить')
                      : widget.submitLabel,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _rowCard(int index, PreferredScheduleDraft row) {
    final days = row.weekdays.toList()..sort();
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
                Text(widget.rowSummary(row)),
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

  Widget _historyReview() {
    final historical = _historical!;
    final count = historical['count'] is num
        ? (historical['count'] as num).toInt()
        : int.tryParse('${historical['count']}') ?? 0;
    return Container(
      key: const Key('schedule-plan-history-review'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.warningSoft,
        border: Border.all(color: AppColor.warning.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Исторические занятия: $count',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            '${historical['from']} — ${historical['until']}. '
            'Подтвердите изменение этого периода расписания.',
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
