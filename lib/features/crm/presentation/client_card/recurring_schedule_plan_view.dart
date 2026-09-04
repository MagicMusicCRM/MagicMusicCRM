import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/models/student_lesson_timeline.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/lesson_state_badges.dart';

typedef SchedulePlanEditIntent =
    void Function(SchedulePlan plan, SchedulePlanRow? row);
typedef SchedulePlanRemoveRowIntent =
    void Function(SchedulePlan plan, SchedulePlanRow row);

class RecurringSchedulePlanView extends StatefulWidget {
  const RecurringSchedulePlanView({
    super.key,
    required this.plans,
    required this.loading,
    required this.error,
    required this.canWrite,
    required this.canCreatePlan,
    required this.groupMode,
    required this.hasGroupMembers,
    required this.fallbackLessons,
    required this.timelinePage,
    required this.timelineLoading,
    required this.timelinePaging,
    required this.timelineError,
    required this.onCreate,
    required this.onRetryPlans,
    required this.onPreviousTimeline,
    required this.onNextTimeline,
    required this.onRetryTimeline,
    required this.onEditPlan,
    required this.onRemoveRow,
    required this.onEditParticipants,
    required this.onEndPlan,
    required this.onOpenTimelineItem,
    this.emptyState,
    this.onOpenFallbackLesson,
  });

  final List<SchedulePlan> plans;
  final bool loading;
  final String? error;
  final bool canWrite;
  final bool canCreatePlan;
  final bool groupMode;
  final bool hasGroupMembers;
  final List<Map<String, dynamic>> fallbackLessons;
  final StudentLessonTimelinePage? timelinePage;
  final bool timelineLoading;
  final bool timelinePaging;
  final String? timelineError;
  final VoidCallback onCreate;
  final VoidCallback onRetryPlans;
  final VoidCallback onPreviousTimeline;
  final VoidCallback onNextTimeline;
  final VoidCallback onRetryTimeline;
  final SchedulePlanEditIntent onEditPlan;
  final SchedulePlanRemoveRowIntent onRemoveRow;
  final ValueChanged<SchedulePlan> onEditParticipants;
  final ValueChanged<SchedulePlan> onEndPlan;
  final Future<void> Function(String lessonId) onOpenTimelineItem;
  final Widget? emptyState;
  final ValueChanged<Map<String, dynamic>>? onOpenFallbackLesson;

  @override
  State<RecurringSchedulePlanView> createState() =>
      _RecurringSchedulePlanViewState();
}

class _RecurringSchedulePlanViewState extends State<RecurringSchedulePlanView> {
  final Set<String> _openingLessonIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final active = widget.plans.where((plan) => plan.isActive).toList();
    final ended = widget.plans.where((plan) => !plan.isActive).toList();
    return SizedBox(
      width: double.infinity,
      child: Column(
        key: const Key('recurring-schedule-plan-section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(),
          if (widget.canWrite && !widget.canCreatePlan)
            Text(
              widget.groupMode
                  ? 'Для группового расписания нужен хотя бы один участник с активным абонементом.'
                  : 'Для нового индивидуального расписания нужен активный абонемент.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          const SizedBox(height: AppSpace.sm),
          if (widget.loading && widget.plans.isEmpty)
            const LinearProgressIndicator(color: AppColor.gold)
          else if (widget.error != null && widget.plans.isEmpty)
            _errorState(widget.onRetryPlans, 'Не удалось загрузить расписание')
          else if (widget.plans.isEmpty)
            _emptyPlans()
          else ...[
            for (final plan in active) ...[
              _planCard(plan, initiallyExpanded: true),
              const SizedBox(height: AppSpace.sm),
            ],
            if (ended.isNotEmpty) _endedPlans(ended),
          ],
          const SizedBox(height: AppSpace.md),
          if (widget.groupMode)
            _GroupLessonList(
              lessons: widget.fallbackLessons,
              onOpen: widget.onOpenFallbackLesson,
            )
          else
            StudentLessonTimelineView(
              page:
                  widget.timelinePage ??
                  const StudentLessonTimelinePage.empty(),
              loading: widget.timelineLoading,
              paging: widget.timelinePaging,
              error: widget.timelineError,
              onPrevious: widget.onPreviousTimeline,
              onNext: widget.onNextTimeline,
              onRetry: widget.onRetryTimeline,
              onOpen: _openTimelineItem,
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader() => LayoutBuilder(
    builder: (context, constraints) => Row(
      children: [
        const Expanded(
          child: Text(
            'Постоянные расписания',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ),
        if (widget.canWrite)
          constraints.maxWidth < 430
              ? IconButton(
                  key: const Key('schedule-plan-add'),
                  onPressed: widget.canCreatePlan ? widget.onCreate : null,
                  tooltip: 'Добавить расписание',
                  icon: const Icon(Icons.add_rounded),
                )
              : TextButton.icon(
                  key: const Key('schedule-plan-add'),
                  onPressed: widget.canCreatePlan ? widget.onCreate : null,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Добавить расписание'),
                ),
      ],
    ),
  );

  Widget _emptyPlans() =>
      widget.emptyState ??
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Постоянных расписаний пока нет',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          Text('Разовые и ранее созданные занятия всё равно показаны ниже.'),
        ],
      );

  Widget _endedPlans(List<SchedulePlan> plans) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(AppRadius.control),
    ),
    child: ExpansionTile(
      key: const PageStorageKey('ended-schedule-plans'),
      initiallyExpanded: false,
      title: Text(
        'Завершённые (${plans.length})',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpace.sm,
        0,
        AppSpace.sm,
        AppSpace.sm,
      ),
      children: [
        for (final plan in plans) ...[
          _planCard(plan, initiallyExpanded: false),
          if (plan != plans.last) const SizedBox(height: AppSpace.sm),
        ],
      ],
    ),
  );

  Widget _planCard(SchedulePlan plan, {required bool initiallyExpanded}) {
    final cs = Theme.of(context).colorScheme;
    final entries = _sortedRuleEntries(plan);
    return Container(
      key: ValueKey('schedule-plan-${plan.id}'),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: plan.isActive ? AppColor.goldLine : cs.outlineVariant,
        ),
      ),
      child: ExpansionTile(
        key: PageStorageKey('schedule-plan-expansion-${plan.id}'),
        initiallyExpanded: initiallyExpanded,
        maintainState: true,
        title: Row(
          children: [
            Expanded(
              child: Text(
                plan.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            _tag(plan.isGroup ? 'Группа' : 'Индивидуально'),
          ],
        ),
        subtitle: Text(
          '${_date(plan.activeFrom)} — ${plan.activeUntil == null ? 'без срока' : _date(plan.activeUntil!)}',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpace.md,
          0,
          AppSpace.md,
          AppSpace.md,
        ),
        children: [
          if (!plan.isActive && plan.endReason?.trim().isNotEmpty == true) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                key: ValueKey('schedule-plan-end-history-${plan.id}'),
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.sm),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Text(
                  'Завершено${plan.endedAt == null ? '' : ' ${_dateTime(plan.endedAt!)}'}'
                  '${plan.endedByName?.trim().isNotEmpty == true ? ' · ${plan.endedByName}' : ''}\n'
                  'Причина: ${plan.endReason!.trim()}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          if (plan.isGroup) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Участников: ${plan.currentParticipants.length}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ),
            const SizedBox(height: AppSpace.xs),
          ],
          if (entries.isEmpty && plan.currentRows.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('В расписании нет строк.'),
            )
          else if (entries.isEmpty)
            for (final row in plan.currentRows) _currentPlanRow(plan, row)
          else
            for (final entry in entries) _timelineRuleRow(plan, entry),
          if (plan.isActive && widget.canWrite) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                if (plan.isGroup)
                  TextButton.icon(
                    key: ValueKey('schedule-plan-participants-${plan.id}'),
                    onPressed: widget.hasGroupMembers
                        ? () => widget.onEditParticipants(plan)
                        : null,
                    icon: const Icon(Icons.group_outlined, size: 17),
                    label: const Text('Участники'),
                  ),
                TextButton.icon(
                  onPressed: () => widget.onEditPlan(plan, null),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Добавить строку'),
                ),
                TextButton.icon(
                  key: ValueKey('schedule-plan-end-${plan.id}'),
                  onPressed: () => widget.onEndPlan(plan),
                  style: TextButton.styleFrom(foregroundColor: cs.error),
                  icon: const Icon(Icons.stop_circle_outlined, size: 17),
                  label: const Text('Завершить'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _currentPlanRow(
    SchedulePlan plan,
    SchedulePlanRow row,
  ) => _ruleSurface(
    values: [
      (Icons.person_outline_rounded, row.teacherName ?? 'Педагог не указан'),
      (Icons.calendar_today_outlined, _weekday(row.weekday)),
      (Icons.schedule_rounded, '${row.beginTime} · ${row.durationMinutes} мин'),
      (
        Icons.date_range_outlined,
        '${_date(row.validFrom)} — ${row.validUntil == null ? 'без срока' : _date(row.validUntil!)}',
      ),
      (Icons.meeting_room_outlined, row.roomName ?? 'Аудитория не указана'),
      (Icons.info_outline_rounded, 'Действует'),
    ],
    actions: _rowActions(plan, row),
  );

  Widget _timelineRuleRow(SchedulePlan plan, ScheduleRuleTimelineEntry entry) {
    final currentRow = plan.currentRows.cast<SchedulePlanRow?>().firstWhere(
      (row) => row?.id == entry.sourceSeriesId || row?.id == entry.id,
      orElse: () => null,
    );
    final isException = entry.kind == ScheduleRuleTimelineKind.datedException;
    final isCurrent =
        !isException &&
        entry.status == ScheduleRuleTimelineStatus.active &&
        currentRow != null;
    final dateValue = isException
        ? '${_weekday(entry.weekday)} · ${_date(entry.scheduledDate ?? entry.activeFrom)}'
        : _weekday(entry.weekday);
    final stateValue = isException
        ? 'Исключение · ${_date(entry.scheduledDate ?? entry.activeFrom)}'
        : entry.status == ScheduleRuleTimelineStatus.active
        ? 'Действует'
        : 'Завершена';
    return _ruleSurface(
      key: ValueKey('schedule-rule-timeline-${entry.id}'),
      values: [
        (
          Icons.person_outline_rounded,
          entry.teacherName ?? 'Педагог не указан',
        ),
        (Icons.calendar_today_outlined, dateValue),
        (
          Icons.schedule_rounded,
          '${entry.beginTime} · ${entry.durationMinutes} мин',
        ),
        (
          Icons.date_range_outlined,
          '${_date(entry.activeFrom)} — ${entry.activeUntil == null ? 'без срока' : _date(entry.activeUntil!)}',
        ),
        (Icons.meeting_room_outlined, entry.roomName ?? 'Аудитория не указана'),
        (Icons.info_outline_rounded, stateValue),
      ],
      actions: isCurrent ? _rowActions(plan, currentRow) : const [],
    );
  }

  List<Widget> _rowActions(SchedulePlan plan, SchedulePlanRow row) {
    if (!plan.isActive || !widget.canWrite) return const [];
    return [
      IconButton(
        key: ValueKey('schedule-plan-row-edit-${row.id}'),
        onPressed: () => widget.onEditPlan(plan, row),
        tooltip: 'Изменить строку с выбранной даты',
        icon: const Icon(Icons.edit_outlined, size: 18),
      ),
      IconButton(
        key: ValueKey('remove-plan-row-${row.id}'),
        onPressed: () => widget.onRemoveRow(plan, row),
        tooltip: 'Удалить строку',
        style: IconButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        icon: const Icon(Icons.delete_outline_rounded, size: 18),
      ),
    ];
  }

  Widget _ruleSurface({
    Key? key,
    required List<(IconData, String)> values,
    required List<Widget> actions,
  }) => Padding(
    padding: const EdgeInsets.only(top: AppSpace.sm),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1040
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final actionWidth = actions.isEmpty ? 0.0 : 48.0;
        final available = (constraints.maxWidth - actionWidth - AppSpace.sm * 2)
            .clamp(1.0, double.infinity);
        final cellWidth = (available - AppSpace.sm * (columns - 1)) / columns;
        return Container(
          key: key,
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    for (final value in values)
                      SizedBox(
                        width: cellWidth,
                        child: _rowValue(value.$1, value.$2),
                      ),
                  ],
                ),
              ),
              if (actions.isNotEmpty)
                Column(mainAxisSize: MainAxisSize.min, children: actions),
            ],
          ),
        );
      },
    ),
  );

  Widget _rowValue(IconData icon, String label) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: AppColor.gold),
      const SizedBox(width: AppSpace.xs),
      Expanded(
        child: Text(
          label,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    ],
  );

  Future<void> _openTimelineItem(StudentLessonTimelineItem item) async {
    final actionableLessonId = item.reschedule.actionableLessonId;
    if (!_openingLessonIds.add(actionableLessonId)) return;
    try {
      await widget.onOpenTimelineItem(actionableLessonId);
    } finally {
      _openingLessonIds.remove(actionableLessonId);
    }
  }

  Widget _tag(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AppColor.goldSoft,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      border: Border.all(color: AppColor.goldLine),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColor.gold,
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _errorState(VoidCallback retry, String message) => Row(
    children: [
      Expanded(
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
      TextButton(onPressed: retry, child: const Text('Повторить')),
    ],
  );
}

class StudentLessonTimelineView extends StatelessWidget {
  const StudentLessonTimelineView({
    super.key,
    required this.page,
    required this.loading,
    required this.paging,
    required this.error,
    required this.onPrevious,
    required this.onNext,
    required this.onRetry,
    required this.onOpen,
  });

  final StudentLessonTimelinePage page;
  final bool loading;
  final bool paging;
  final String? error;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onRetry;
  final ValueChanged<StudentLessonTimelineItem> onOpen;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('student-lesson-timeline'),
    width: double.infinity,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: AppColor.goldLine),
      borderRadius: BorderRadius.circular(AppRadius.control),
    ),
    padding: const EdgeInsets.all(AppSpace.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Лента занятий',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              key: const Key('student-lesson-timeline-previous'),
              onPressed: page.hasPrevious && !paging ? onPrevious : null,
              tooltip: 'Предыдущие занятия',
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              key: const Key('student-lesson-timeline-next'),
              onPressed: page.hasNext && !paging ? onNext : null,
              tooltip: 'Следующие занятия',
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        if (loading && page.items.isEmpty)
          const LinearProgressIndicator(color: AppColor.gold)
        else if (error != null && page.items.isEmpty)
          _timelineError(context)
        else if (page.items.isEmpty)
          Text(
            'Занятий пока нет.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          )
        else
          for (var index = 0; index < page.items.length; index++) ...[
            _StudentTimelineItem(
              item: page.items[index],
              onTap: () => onOpen(page.items[index]),
            ),
            if (index != page.items.length - 1)
              const SizedBox(height: AppSpace.xs),
          ],
        if (error != null && page.items.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          _timelineError(context),
        ],
        if (paging) ...[
          const SizedBox(height: AppSpace.sm),
          const LinearProgressIndicator(color: AppColor.gold),
        ],
      ],
    ),
  );

  Widget _timelineError(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          error ?? 'Не удалось загрузить занятия.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      ),
      TextButton(onPressed: onRetry, child: const Text('Повторить')),
    ],
  );
}

class _StudentTimelineItem extends StatelessWidget {
  const _StudentTimelineItem({required this.item, required this.onTap});

  final StudentLessonTimelineItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = LessonStateProjection.fromMap({
      'lifecycle_state': _lifecycleWire(item.lifecycleState),
    });
    final local = item.scheduledAt.toLocal();
    final details = <String>[
      '${DateFormat('dd.MM.yyyy HH:mm').format(local)} · ${item.durationMinutes} мин',
      item.teacher?.name ?? 'Педагог не указан',
      item.room?.name ?? 'Аудитория не указана',
    ];
    final hasActionableSuccessor =
        item.lifecycleState == StudentLessonLifecycleState.rescheduled &&
        item.reschedule.successorId != null;
    final relation = item.reschedule.predecessorId != null
        ? 'Новое занятие после переноса'
        : null;
    return InkWell(
      key: ValueKey('student-timeline-${item.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: state.token.soft,
          border: Border.all(color: state.token.accent.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final title = Row(
              children: [
                Icon(state.token.icon, size: 17, color: state.token.accent),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    _originLabel(item.origin.kind),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (item.settlement.coveredBySubscription)
                  const LessonSubscriptionBadge(),
              ],
            );
            final metadata = Wrap(
              spacing: AppSpace.md,
              runSpacing: AppSpace.xs,
              children: [
                for (final detail in details)
                  Text(detail, style: const TextStyle(fontSize: 12)),
                Text(
                  state.label,
                  style: TextStyle(
                    color: state.token.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (relation != null)
                  Text(relation, style: const TextStyle(fontSize: 12)),
                if (hasActionableSuccessor)
                  TextButton(
                    key: ValueKey('student-timeline-successor-${item.id}'),
                    onPressed: onTap,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColor.text2,
                      minimumSize: Size.zero,
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Открыть актуальное занятие',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            );
            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      const SizedBox(height: AppSpace.xs),
                      metadata,
                    ],
                  )
                : Row(
                    children: [
                      SizedBox(width: 220, child: title),
                      const SizedBox(width: AppSpace.md),
                      Expanded(child: metadata),
                    ],
                  );
          },
        ),
      ),
    );
  }
}

class _GroupLessonList extends StatelessWidget {
  const _GroupLessonList({required this.lessons, required this.onOpen});

  final List<Map<String, dynamic>> lessons;
  final ValueChanged<Map<String, dynamic>>? onOpen;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('group-lesson-list'),
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpace.md),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(AppRadius.control),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Занятия группы',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpace.sm),
        if (lessons.isEmpty)
          const Text('Занятий группы пока нет.')
        else
          for (final lesson in lessons)
            ListTile(
              key: ValueKey('group-lesson-${lesson['id']}'),
              contentPadding: EdgeInsets.zero,
              title: Text(_groupLessonDate(lesson)),
              subtitle: Text(
                (lesson['teacher_name'] ??
                        lesson['teacherName'] ??
                        'Педагог не указан')
                    .toString(),
              ),
              onTap: onOpen == null ? null : () => onOpen!(lesson),
            ),
      ],
    ),
  );
}

List<ScheduleRuleTimelineEntry> _sortedRuleEntries(SchedulePlan plan) {
  final byId = <String, ScheduleRuleTimelineEntry>{};
  for (final entry in [...plan.ruleTimeline, ...plan.exceptions]) {
    byId[entry.id] = entry;
  }
  final entries = byId.values.toList();
  entries.sort((left, right) {
    final bucket = left.sortBucket.compareTo(right.sortBucket);
    if (bucket != 0) return bucket;
    final at = left.sortBucket == 3
        ? right.sortAt.compareTo(left.sortAt)
        : left.sortAt.compareTo(right.sortAt);
    return at != 0 ? at : left.id.compareTo(right.id);
  });
  return entries;
}

String _date(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null ? value : DateFormat('d.MM.yyyy').format(parsed);
}

String _dateTime(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null
      ? value
      : DateFormat('dd.MM.yyyy HH:mm').format(parsed.toLocal());
}

String _weekday(int value) => const [
  'понедельник',
  'вторник',
  'среда',
  'четверг',
  'пятница',
  'суббота',
  'воскресенье',
][value.clamp(1, 7) - 1];

String _originLabel(StudentLessonOriginKind kind) => switch (kind) {
  StudentLessonOriginKind.manual => 'Разовое занятие',
  StudentLessonOriginKind.schedulePlan => 'Постоянное расписание',
  StudentLessonOriginKind.oneOffException => 'Исключение расписания',
};

String _lifecycleWire(StudentLessonLifecycleState state) => switch (state) {
  StudentLessonLifecycleState.scheduled => 'scheduled',
  StudentLessonLifecycleState.settlementPending => 'settlement_pending',
  StudentLessonLifecycleState.successfullyCompleted => 'successfully_completed',
  StudentLessonLifecycleState.cancelled => 'cancelled',
  StudentLessonLifecycleState.rescheduled => 'rescheduled',
};

String _groupLessonDate(Map<String, dynamic> lesson) {
  final raw = lesson['scheduled_at'] ?? lesson['scheduledAt'];
  final parsed = DateTime.tryParse(raw?.toString() ?? '');
  return parsed == null
      ? 'Дата не указана'
      : DateFormat('dd.MM.yyyy HH:mm').format(parsed.toLocal());
}
