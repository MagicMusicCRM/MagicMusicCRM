import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/lesson_state_badges.dart';

typedef SchedulePlanPageIntent =
    void Function(SchedulePlan plan, String direction);
typedef SchedulePlanEditIntent =
    void Function(SchedulePlan plan, SchedulePlanRow? row);

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
    required this.trays,
    required this.loadingTrayIds,
    required this.trayErrors,
    required this.onCreate,
    required this.onRetryPlans,
    required this.onEnsureTray,
    required this.onPageTray,
    required this.onRetryTray,
    required this.onEditPlan,
    required this.onEditParticipants,
    required this.onEndPlan,
    required this.onOpenTrayItem,
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
  final Map<String, SchedulePlanTrayPage> trays;
  final Set<String> loadingTrayIds;
  final Map<String, String> trayErrors;
  final VoidCallback onCreate;
  final VoidCallback onRetryPlans;
  final ValueChanged<SchedulePlan> onEnsureTray;
  final SchedulePlanPageIntent onPageTray;
  final ValueChanged<SchedulePlan> onRetryTray;
  final SchedulePlanEditIntent onEditPlan;
  final ValueChanged<SchedulePlan> onEditParticipants;
  final ValueChanged<SchedulePlan> onEndPlan;
  final Future<void> Function(SchedulePlanTrayItem item) onOpenTrayItem;
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
    return Column(
      key: const Key('recurring-schedule-plan-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
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
                        onPressed: widget.canCreatePlan
                            ? widget.onCreate
                            : null,
                        tooltip: 'Добавить расписание',
                        icon: const Icon(Icons.add_rounded),
                      )
                    : TextButton.icon(
                        key: const Key('schedule-plan-add'),
                        onPressed: widget.canCreatePlan
                            ? widget.onCreate
                            : null,
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text('Добавить расписание'),
                      ),
            ],
          ),
        ),
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
          _errorState(widget.onRetryPlans)
        else if (widget.plans.isEmpty)
          _emptyPlans()
        else ...[
          for (final plan in active) ...[
            _planCard(plan, initiallyExpanded: true),
            const SizedBox(height: AppSpace.sm),
          ],
          if (ended.isNotEmpty) _endedPlans(ended),
        ],
      ],
    );
  }

  Widget _emptyPlans() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.emptyState ??
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Постоянных расписаний пока нет',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Разовые и ранее созданные занятия всё равно показаны ниже.',
                ),
              ],
            ),
        if (widget.fallbackLessons.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          _FallbackLessonTray(
            lessons: widget.fallbackLessons,
            onOpenLesson: widget.onOpenFallbackLesson,
          ),
        ],
      ],
    );
  }

  Widget _endedPlans(List<SchedulePlan> plans) {
    return Container(
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
  }

  Widget _planCard(SchedulePlan plan, {required bool initiallyExpanded}) {
    final cs = Theme.of(context).colorScheme;
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
        onExpansionChanged: (expanded) {
          if (expanded) widget.onEnsureTray(plan);
        },
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
          '${_date(plan.activeFrom)} - ${plan.activeUntil == null ? 'без срока' : _date(plan.activeUntil!)}',
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
          if (plan.currentRows.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('В расписании нет активных строк.'),
            )
          else
            for (final row in plan.currentRows) _planRow(plan, row),
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
          const Divider(height: AppSpace.lg),
          _planTray(plan),
        ],
      ),
    );
  }

  Widget _planRow(SchedulePlan plan, SchedulePlanRow row) {
    final cs = Theme.of(context).colorScheme;
    final period =
        '${_date(row.validFrom)} - '
        '${row.validUntil == null ? 'без срока' : _date(row.validUntil!)}';
    final values = [
      (Icons.person_outline_rounded, row.teacherName ?? 'Педагог не указан'),
      (Icons.calendar_today_outlined, _weekday(row.weekday)),
      (Icons.schedule_rounded, '${row.beginTime} · ${row.durationMinutes} мин'),
      (Icons.date_range_outlined, period),
      (Icons.meeting_room_outlined, row.roomName ?? 'Аудитория не указана'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final editable = plan.isActive && widget.canWrite;
          final contentWidth =
              constraints.maxWidth - AppSpace.sm * 2 - (editable ? 48 : 0);
          final content = compact
              ? Wrap(
                  spacing: AppSpace.md,
                  runSpacing: AppSpace.sm,
                  children: [
                    for (final value in values)
                      SizedBox(
                        width: contentWidth < 430
                            ? contentWidth
                            : (contentWidth - AppSpace.md) / 2,
                        child: _rowValue(value.$1, value.$2),
                      ),
                  ],
                )
              : Row(
                  children: [
                    for (final value in values)
                      Expanded(child: _rowValue(value.$1, value.$2)),
                  ],
                );
          return DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: content),
                  if (editable)
                    IconButton(
                      key: ValueKey('schedule-plan-row-edit-${row.id}'),
                      onPressed: () => widget.onEditPlan(plan, row),
                      tooltip: 'Изменить строку с выбранной даты',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _rowValue(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: AppColor.gold),
      const SizedBox(width: AppSpace.xs),
      Flexible(
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    ],
  );

  Widget _planTray(SchedulePlan plan) {
    final page = widget.trays[plan.id];
    if (widget.loadingTrayIds.contains(plan.id) && page == null) {
      return const LinearProgressIndicator(color: AppColor.gold);
    }
    final error = widget.trayErrors[plan.id];
    if (error != null && page == null) {
      return _errorState(() => widget.onRetryTray(plan));
    }
    if (page == null) {
      return TextButton(
        onPressed: () => widget.onEnsureTray(plan),
        child: const Text('Показать занятия'),
      );
    }
    final firstItem = page.items.firstOrNull;
    final lastItem = page.items.lastOrNull;
    final pageRange = firstItem == null
        ? null
        : firstItem.id == lastItem?.id
        ? '${_date(firstItem.localDate)} · ${firstItem.localTime}'
        : '${_date(firstItem.localDate)} - ${_date(lastItem!.localDate)} · ${page.items.length}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Лента занятий',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  if (plan.scheduledLessonCount != null)
                    Text(
                      'Запланировано: ${plan.scheduledLessonCount}'
                      '${plan.coveredLessonCount == null ? '' : ' · Покрыто абонементом: ${plan.coveredLessonCount}'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  if (pageRange != null)
                    Text(
                      pageRange,
                      key: ValueKey('schedule-plan-tray-range-${plan.id}'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('schedule-plan-tray-previous-${plan.id}'),
              onPressed:
                  page.hasPrevious && !widget.loadingTrayIds.contains(plan.id)
                  ? () => widget.onPageTray(plan, 'previous')
                  : null,
              tooltip: 'Предыдущие занятия',
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              key: ValueKey('schedule-plan-tray-next-${plan.id}'),
              onPressed:
                  page.hasNext && !widget.loadingTrayIds.contains(plan.id)
                  ? () => widget.onPageTray(plan, 'next')
                  : null,
              tooltip: 'Следующие занятия',
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        if (page.items.isEmpty)
          Text(
            'Занятий в этом расписании пока нет.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          )
        else
          _LessonTrayGrid(
            key: ValueKey('schedule-plan-tray-${plan.id}'),
            storageKey:
                '${plan.id}:${firstItem?.id ?? 'empty'}:${lastItem?.id ?? 'empty'}',
            items: page.items,
            onOpen: _openTrayItem,
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Row(
              key: ValueKey('schedule-plan-tray-page-error-${plan.id}'),
              children: [
                Expanded(
                  child: Text(
                    'Не удалось перелистнуть занятия.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(
                  key: ValueKey('schedule-plan-tray-retry-${plan.id}'),
                  onPressed: () => widget.onRetryTray(plan),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        if (widget.loadingTrayIds.contains(plan.id))
          const LinearProgressIndicator(color: AppColor.gold),
      ],
    );
  }

  Future<void> _openTrayItem(SchedulePlanTrayItem item) async {
    if (!widget.canWrite || !_openingLessonIds.add(item.id)) return;
    try {
      await widget.onOpenTrayItem(item);
    } finally {
      _openingLessonIds.remove(item.id);
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

  Widget _errorState(VoidCallback retry) => Row(
    children: [
      Expanded(
        child: Text(
          'Не удалось загрузить расписание',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
      TextButton(onPressed: retry, child: const Text('Повторить')),
    ],
  );
}

class _LessonTrayGrid extends StatelessWidget {
  const _LessonTrayGrid({
    super.key,
    required this.storageKey,
    required this.items,
    required this.onOpen,
  });

  final String storageKey;
  final List<SchedulePlanTrayItem> items;
  final ValueChanged<SchedulePlanTrayItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentColumns = max(1, (items.length / 2).ceil());
        final visibleColumns = ((constraints.maxWidth + 4) / 82).floor().clamp(
          1,
          contentColumns,
        );
        final tileWidth =
            (constraints.maxWidth - (visibleColumns - 1) * 4) / visibleColumns;
        return SizedBox(
          key: const Key('client-lesson-date-tray'),
          height: 84,
          child: GridView.builder(
            key: PageStorageKey('client-lesson-date-tray-$storageKey'),
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: tileWidth,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => _TrayTile(
              item: items[index],
              onTap: () => onOpen(items[index]),
            ),
          ),
        );
      },
    );
  }
}

class _TrayTile extends StatelessWidget {
  const _TrayTile({required this.item, required this.onTap});

  final SchedulePlanTrayItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = LessonStateProjection.fromMap({
      'lifecycle_state': item.state,
    });
    final marker = item.settlementMarkers.firstOrNull;
    final covered = lessonHasSubscriptionCoverage({
      'settlementMarkers': item.settlementMarkers,
    });
    final accent = state.token.accent;
    final markerAccent = marker == null
        ? accent
        : lessonDecisionColorToken(marker['colorToken']?.toString());
    final markerLabels = item.settlementMarkers
        .map((value) => value['label']?.toString())
        .whereType<String>();
    final relationLabel = _relationMarkerLabel(item.relationMarker);
    final tooltip = [
      '${_date(item.localDate)} ${item.localTime}',
      state.label,
      ...markerLabels,
      ?relationLabel,
      ?item.teacherName,
      ?item.roomName,
    ].join('\n');
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: ValueKey('client-lesson-${item.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          decoration: BoxDecoration(
            color: state.token.soft,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: accent.withValues(alpha: 0.55)),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_shortDate(item.localDate)} · ${item.localTime}',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_stateIcon(item.state), size: 10, color: accent),
                        if (covered) ...[
                          const SizedBox(width: 4),
                          const LessonSubscriptionBadge(compact: true),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (marker != null && !covered)
                Positioned(
                  top: 2,
                  right: 3,
                  child: Icon(
                    Icons.sell_outlined,
                    size: 9,
                    color: markerAccent,
                  ),
                ),
              if (item.relationMarker != 'none')
                Positioned(
                  bottom: 1,
                  left: 2,
                  child: Icon(
                    item.relationMarker == 'source'
                        ? Icons.call_split_rounded
                        : Icons.call_merge_rounded,
                    size: 9,
                    color: accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FallbackLessonTray extends StatelessWidget {
  const _FallbackLessonTray({required this.lessons, this.onOpenLesson});

  final List<Map<String, dynamic>> lessons;
  final ValueChanged<Map<String, dynamic>>? onOpenLesson;

  @override
  Widget build(BuildContext context) {
    final sorted =
        lessons
            .map((lesson) {
              final raw = lesson['scheduled_at'] ?? lesson['scheduledAt'];
              final scheduled = DateTime.tryParse(raw?.toString() ?? '');
              if (scheduled == null) return null;
              final projection = LessonStateProjection.fromMap(lesson);
              return SchedulePlanTrayItem(
                id: lesson['id']?.toString() ?? '',
                scheduledAt: scheduled.toIso8601String(),
                localDate: DateFormat('yyyy-MM-dd').format(scheduled.toLocal()),
                localTime: DateFormat('HH:mm').format(scheduled.toLocal()),
                state: projection.state,
                settlementMarkers: [
                  if (lessonHasSubscriptionCoverage(lesson))
                    {
                      'key': 'subscription_reserved',
                      'label': 'Покрыто абонементом',
                      'colorToken': 'success',
                    },
                  if ((lesson['paid_amount'] ?? lesson['paidAmount']) != null)
                    {'label': 'Есть платёж', 'colorToken': 'success'},
                  if ((lesson['is_trial'] ?? lesson['isTrial']) == true)
                    {'label': 'Пробное занятие', 'colorToken': 'warning'},
                ],
                relationMarker: 'none',
                predecessorId: null,
                successorId: null,
                teacherName: (lesson['teacher_name'] ?? lesson['teacherName'])
                    ?.toString(),
                roomName: (lesson['room_name'] ?? lesson['roomName'])
                    ?.toString(),
              );
            })
            .whereType<SchedulePlanTrayItem>()
            .toList()
          ..sort(
            (left, right) => left.scheduledAt.compareTo(right.scheduledAt),
          );
    final rawById = {
      for (final lesson in lessons) lesson['id']?.toString(): lesson,
    };
    return _LessonTrayGrid(
      storageKey: 'fallback-lessons',
      items: sorted,
      onOpen: (item) {
        final lesson = rawById[item.id];
        if (lesson != null) onOpenLesson?.call(lesson);
      },
    );
  }
}

String _date(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null ? value : DateFormat('dd.MM.yyyy').format(parsed);
}

String _dateTime(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null
      ? value
      : DateFormat('dd.MM.yyyy HH:mm').format(parsed.toLocal());
}

String _shortDate(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null ? value : DateFormat('d.MM').format(parsed);
}

String? _relationMarkerLabel(String marker) => switch (marker) {
  'source' => 'Перенос: исходное занятие',
  'successor' => 'Перенос: новое занятие',
  _ => null,
};

String _weekday(int value) =>
    const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][value.clamp(1, 7) - 1];

IconData _stateIcon(String state) => switch (state) {
  'successfully_completed' => Icons.check_rounded,
  'settlement_pending' => Icons.hourglass_top_rounded,
  'cancelled' => Icons.close_rounded,
  'rescheduled' => Icons.swap_horiz_rounded,
  _ => Icons.event_rounded,
};
