import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision_flow.dart';

import 'preferred_schedule_editor.dart';
import 'group_schedule_participants_editor.dart';
import 'recurring_schedule_plan_controller.dart';

class RecurringSchedulePlanSection extends ConsumerStatefulWidget {
  const RecurringSchedulePlanSection({
    super.key,
    this.studentId,
    this.groupId,
    this.subjectName,
    required this.fallbackLessons,
    required this.branches,
    required this.defaultBranchId,
    required this.subscriptions,
    required this.canWrite,
    required this.onChanged,
    this.onOpenLesson,
    this.groupMembers = const [],
  }) : assert((studentId == null) != (groupId == null));

  final String? studentId;
  final String? groupId;
  final String? subjectName;
  final List<Map<String, dynamic>> fallbackLessons;
  final List<Map<String, dynamic>> branches;
  final String? defaultBranchId;
  final List<Map<String, dynamic>> subscriptions;
  final bool canWrite;
  final VoidCallback onChanged;
  final ValueChanged<Map<String, dynamic>>? onOpenLesson;
  final List<GroupScheduleMemberOption> groupMembers;

  @override
  ConsumerState<RecurringSchedulePlanSection> createState() =>
      _RecurringSchedulePlanSectionState();
}

class _RecurringSchedulePlanSectionState
    extends ConsumerState<RecurringSchedulePlanSection> {
  late RecurringSchedulePlanController _controller;
  final Set<String> _openingLessonIds = <String>{};

  MagicCrmService get _crm => ref.read(magicCrmServiceProvider);

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant RecurringSchedulePlanSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId ||
        oldWidget.groupId != widget.groupId) {
      _controller.dispose();
      _createController();
    }
  }

  void _createController() {
    _controller = RecurringSchedulePlanController(
      service: _crm,
      studentId: widget.studentId,
      groupId: widget.groupId,
    )..load();
  }

  bool get _groupMode => widget.groupId != null;

  bool get _canCreatePlan => _groupMode
      ? widget.groupMembers.any((member) => member.hasSubscription)
      : widget.subscriptions.isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final active = _controller.plans
            .where((plan) => plan.isActive)
            .toList();
        final ended = _controller.plans
            .where((plan) => !plan.isActive)
            .toList();
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (widget.canWrite)
                    constraints.maxWidth < 430
                        ? IconButton(
                            key: const Key('schedule-plan-add'),
                            onPressed: _canCreatePlan ? _createPlan : null,
                            tooltip: 'Добавить расписание',
                            icon: const Icon(Icons.add_rounded),
                          )
                        : TextButton.icon(
                            key: const Key('schedule-plan-add'),
                            onPressed: _canCreatePlan ? _createPlan : null,
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: const Text('Добавить расписание'),
                          ),
                ],
              ),
            ),
            if (widget.canWrite && !_canCreatePlan)
              Text(
                _groupMode
                    ? 'Для группового расписания нужен хотя бы один участник с активным абонементом.'
                    : 'Для нового индивидуального расписания нужен активный абонемент.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: AppSpace.sm),
            if (_controller.loading && _controller.plans.isEmpty)
              const LinearProgressIndicator(color: AppColor.gold)
            else if (_controller.error != null && _controller.plans.isEmpty)
              _errorState(_controller.error!, _controller.load)
            else if (_controller.plans.isEmpty)
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
      },
    );
  }

  Widget _emptyPlans() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MagicPageState(
          kind: MagicPageStateKind.empty,
          title: 'Постоянных расписаний пока нет',
          message: 'Разовые и ранее созданные занятия всё равно показаны ниже.',
        ),
        if (widget.fallbackLessons.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          _FallbackLessonTray(
            lessons: widget.fallbackLessons,
            onOpenLesson: widget.onOpenLesson,
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
          if (expanded) _controller.ensureTray(plan);
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
                    onPressed: widget.groupMembers.isEmpty
                        ? null
                        : () => _editParticipants(plan),
                    icon: const Icon(Icons.group_outlined, size: 17),
                    label: const Text('Участники'),
                  ),
                TextButton.icon(
                  onPressed: () => _editPlan(plan),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Добавить строку'),
                ),
                TextButton.icon(
                  key: ValueKey('schedule-plan-end-${plan.id}'),
                  onPressed: () => _endPlan(plan),
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
        '${_date(row.validFrom)} — '
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
                      onPressed: () => _editPlan(plan, row: row),
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
    final page = _controller.trays[plan.id];
    if (_controller.loadingTrays.contains(plan.id) && page == null) {
      return const LinearProgressIndicator(color: AppColor.gold);
    }
    final error = _controller.trayErrors[plan.id];
    if (error != null && page == null) {
      return _errorState(error, () => _controller.retryTray(plan));
    }
    if (page == null) {
      return TextButton(
        onPressed: () => _controller.ensureTray(plan),
        child: const Text('Показать занятия'),
      );
    }
    final firstItem = page.items.firstOrNull;
    final lastItem = page.items.lastOrNull;
    final pageRange = firstItem == null
        ? null
        : firstItem.id == lastItem?.id
        ? '${_date(firstItem.localDate)} · ${firstItem.localTime}'
        : '${_date(firstItem.localDate)} — ${_date(lastItem!.localDate)} · ${page.items.length}';
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
                  page.hasPrevious &&
                      !_controller.loadingTrays.contains(plan.id)
                  ? () => _controller.pageTray(plan, 'previous')
                  : null,
              tooltip: 'Предыдущие занятия',
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              key: ValueKey('schedule-plan-tray-next-${plan.id}'),
              onPressed:
                  page.hasNext && !_controller.loadingTrays.contains(plan.id)
                  ? () => _controller.pageTray(plan, 'next')
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
                  onPressed: () => _controller.retryTray(plan),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        if (_controller.loadingTrays.contains(plan.id))
          const LinearProgressIndicator(color: AppColor.gold),
      ],
    );
  }

  Future<void> _openTrayItem(SchedulePlanTrayItem item) async {
    if (!widget.canWrite || !_openingLessonIds.add(item.id)) return;
    try {
      var lesson = widget.fallbackLessons
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (candidate) => candidate?['id']?.toString() == item.id,
            orElse: () => null,
          );
      if (lesson == null) {
        final exact = await _crm.listLessons(lessonId: item.id, limit: 1);
        lesson = exact.firstOrNull;
      }
      if (!mounted) return;
      if (lesson == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Занятие больше недоступно. Обновите расписание.'),
          ),
        );
        return;
      }

      final externalOpen = widget.onOpenLesson;
      if (externalOpen != null) {
        externalOpen(lesson);
        return;
      }

      final changed = await CreateLessonDialog.show(context, lesson: lesson);
      if (changed == true && mounted) {
        widget.onChanged();
        await _controller.load();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось открыть занятие. Повторите попытку.'),
        ),
      );
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

  Widget _errorState(String error, VoidCallback retry) => Row(
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

  Future<
    ({
      List<Map<String, dynamic>> teachers,
      List<Map<String, dynamic>> rooms,
      Map<String, LessonDecisionCatalog> decisionCatalogs,
    })
  >
  _references() async {
    final teachersFuture = _crm.listTeachers(limit: 100);
    final roomsFuture = _crm.listRooms(limit: 100);
    final api = ref.read(magicApiClientProvider);
    final catalogsFuture = Future.wait<Map<String, dynamic>>([
      for (final branch in widget.branches)
        api.get<Map<String, dynamic>>(
          '/crm/configuration/lesson-decisions',
          queryParameters: {'branchId': branch['id']?.toString()},
        ),
    ]);
    final teachers = await teachersFuture;
    final rooms = await roomsFuture;
    final rawCatalogs = await catalogsFuture;
    return (
      teachers: List<Map<String, dynamic>>.from(teachers),
      rooms: List<Map<String, dynamic>>.from(rooms),
      decisionCatalogs: {
        for (var index = 0; index < widget.branches.length; index++)
          if (widget.branches[index]['id']?.toString().isNotEmpty == true)
            widget.branches[index]['id']
                .toString(): LessonDecisionCatalog.fromJson(
              rawCatalogs[index],
              LessonDecisionOperation.settle,
            ),
      },
    );
  }

  Future<void> _createPlan() async {
    try {
      GroupScheduleParticipantsDraft? participantDraft;
      if (_groupMode) {
        participantDraft = await showMagicSheet<GroupScheduleParticipantsDraft>(
          context,
          title: 'Участники группового расписания',
          subtitle: 'Выберите учеников и их абонементы',
          icon: Icons.groups_rounded,
          builder: (_) =>
              GroupScheduleParticipantsEditor(members: widget.groupMembers),
        );
        if (participantDraft == null || !mounted) return;
      }
      final references = await _references();
      if (!mounted) return;
      final draft = await showMagicSheet<PreferredScheduleDraft>(
        context,
        title: 'Новое постоянное расписание',
        subtitle: 'Можно создать несколько дней и занятий одной командой',
        icon: Icons.event_repeat_rounded,
        builder: (_) => PreferredScheduleEditor(
          planMode: true,
          initialTitle: _groupMode
              ? (widget.subjectName?.trim().isNotEmpty == true
                    ? widget.subjectName!.trim()
                    : 'Групповые занятия')
              : 'Индивидуальные занятия',
          subscriptionOptions: _groupMode ? const [] : widget.subscriptions,
          initialSubscriptionId: _groupMode
              ? null
              : widget.subscriptions.first['id']?.toString(),
          requireSubscription: !_groupMode,
          allowOpenEnded: true,
          branches: widget.branches,
          teachers: references.teachers,
          rooms: references.rooms,
          defaultBranchId: widget.defaultBranchId,
          decisionCatalogs: references.decisionCatalogs,
        ),
      );
      if (draft == null || !mounted) return;
      final rowDrafts = await showMagicSheet<List<PreferredScheduleDraft>>(
        context,
        title: 'Проверка постоянного расписания',
        subtitle:
            'Добавьте отдельный набор дней для другого педагога или аудитории',
        icon: Icons.rule_rounded,
        builder: (_) => _SchedulePlanRowsReview(
          initialRows: [draft],
          branches: widget.branches,
          teachers: references.teachers,
          rooms: references.rooms,
          defaultBranchId: widget.defaultBranchId,
          decisionCatalogs: references.decisionCatalogs,
          participantLabels: _participantLabels,
          onValidate: (rows) => _crm.previewSchedulePlanConstraints(
            title: draft.title!,
            kind: _groupMode ? 'group' : 'individual',
            studentId: widget.studentId,
            groupId: widget.groupId,
            subscriptionId: draft.subscriptionId,
            participants: participantDraft?.participants ?? const [],
            activeFrom: _apiDate(draft.validFrom),
            activeUntil: draft.openEnded ? null : _apiDate(draft.validUntil),
            rows: [for (final row in rows) ..._draftRows(row)],
          ),
        ),
      );
      if (rowDrafts == null || !mounted) return;
      await _crm.createSchedulePlan(
        identity: MagicMutationIdentity.create('schedule-plan-create'),
        title: draft.title!,
        kind: _groupMode ? 'group' : 'individual',
        studentId: widget.studentId,
        groupId: widget.groupId,
        subscriptionId: draft.subscriptionId,
        participants: participantDraft?.participants ?? const [],
        activeFrom: _apiDate(draft.validFrom),
        activeUntil: draft.openEnded ? null : _apiDate(draft.validUntil),
        rows: [for (final row in rowDrafts) ..._draftRows(row)],
      );
      await _reload('Расписание создано');
    } catch (error) {
      _showError('Не удалось создать расписание', error);
    }
  }

  Future<void> _editPlan(SchedulePlan plan, {SchedulePlanRow? row}) async {
    try {
      final references = await _references();
      if (!mounted) return;
      final source = row == null
          ? null
          : <String, dynamic>{
              'id': row.id,
              'teacher_id': row.teacherId,
              'room_id': row.roomId,
              'branch_id': row.branchId,
              'weekday': row.weekday,
              'begin_time': row.beginTime,
              'duration_minutes': row.durationMinutes,
              'valid_from': _apiDate(DateTime.now()),
              'valid_until': plan.activeUntil,
              'notes': row.notes,
              'financial_decision': row.financialDecision,
            };
      final draft = await showMagicSheet<PreferredScheduleDraft>(
        context,
        title: row == null ? 'Добавить строку' : 'Изменить строку',
        subtitle: 'Прошедшие занятия и снимки не изменятся',
        icon: Icons.edit_calendar_outlined,
        builder: (_) => PreferredScheduleEditor(
          planMode: true,
          initialTitle: plan.title,
          subscriptionOptions: plan.isGroup ? const [] : widget.subscriptions,
          initialSubscriptionId: plan.subscriptionId,
          requireSubscription: !plan.isGroup,
          allowOpenEnded: true,
          branches: widget.branches,
          teachers: references.teachers,
          rooms: references.rooms,
          defaultBranchId: widget.defaultBranchId,
          series: source,
          decisionCatalogs: references.decisionCatalogs,
        ),
      );
      if (draft == null || !mounted) return;
      final rows = plan.currentRows
          .map(
            (item) => _draftFromPlanRow(
              item,
              validFrom: draft.validFrom,
              validUntil: draft.validUntil,
              title: draft.title,
              subscriptionId: draft.subscriptionId,
              openEnded: draft.openEnded,
            ),
          )
          .toList();
      if (row == null) {
        rows.add(draft);
      } else {
        final index = rows.indexWhere((item) => item.seriesId == row.id);
        rows[index] = draft;
      }
      final reviewedRows = await showMagicSheet<List<PreferredScheduleDraft>>(
        context,
        title: 'Проверка изменений расписания',
        subtitle: 'Все строки проверяются до сохранения изменений',
        icon: Icons.rule_rounded,
        builder: (_) => _SchedulePlanRowsReview(
          initialRows: rows,
          branches: widget.branches,
          teachers: references.teachers,
          rooms: references.rooms,
          defaultBranchId: widget.defaultBranchId,
          decisionCatalogs: references.decisionCatalogs,
          participantLabels: _participantLabels,
          submitLabel: 'Проверить и сохранить',
          onValidate: (reviewRows) => _crm.previewSchedulePlanUpdateConstraints(
            plan.id,
            expectedVersion: plan.version,
            effectiveFrom: _apiDate(draft.validFrom),
            title: draft.title!,
            subscriptionId: plan.isGroup ? null : draft.subscriptionId,
            activeUntil: draft.openEnded ? null : _apiDate(draft.validUntil),
            rows: [
              for (final reviewRow in reviewRows) ..._draftRows(reviewRow),
            ],
          ),
        ),
      );
      if (reviewedRows == null || !mounted) return;
      await _crm.updateSchedulePlan(
        plan.id,
        identity: MagicMutationIdentity.create('schedule-plan-update'),
        expectedVersion: plan.version,
        effectiveFrom: _apiDate(draft.validFrom),
        title: draft.title!,
        subscriptionId: plan.isGroup ? null : draft.subscriptionId,
        activeUntil: draft.openEnded ? null : _apiDate(draft.validUntil),
        rows: [
          for (final reviewedRow in reviewedRows) ..._draftRows(reviewedRow),
        ],
      );
      await _reload('Расписание обновлено');
    } catch (error) {
      _showError('Не удалось обновить расписание', error);
    }
  }

  Future<void> _editParticipants(SchedulePlan plan) async {
    if (!plan.isGroup || widget.groupMembers.isEmpty) return;
    try {
      final draft = await showMagicSheet<GroupScheduleParticipantsDraft>(
        context,
        title: 'Участники «${plan.title}»',
        subtitle: 'Изменение действует только для занятий с выбранной даты',
        icon: Icons.group_outlined,
        builder: (_) => GroupScheduleParticipantsEditor(
          members: widget.groupMembers,
          initialParticipants: plan.currentParticipants,
          requireEffectiveFrom: true,
        ),
      );
      if (draft == null || !mounted || draft.effectiveFrom == null) return;
      final references = await _references();
      if (!mounted) return;
      final effectiveFrom = draft.effectiveFrom!;
      final validUntil =
          DateTime.tryParse(plan.activeUntil ?? '') ??
          effectiveFrom.add(const Duration(days: 90));
      final rows = plan.currentRows
          .map(
            (row) => _draftFromPlanRow(
              row,
              validFrom: effectiveFrom,
              validUntil: validUntil,
              title: plan.title,
              subscriptionId: plan.subscriptionId,
              openEnded: plan.activeUntil == null,
            ),
          )
          .toList();
      final reviewedRows = await showMagicSheet<List<PreferredScheduleDraft>>(
        context,
        title: 'Проверка расписания участников',
        subtitle: 'Проверяем каждого выбранного ученика по всем строкам',
        icon: Icons.rule_rounded,
        builder: (_) => _SchedulePlanRowsReview(
          initialRows: rows,
          branches: widget.branches,
          teachers: references.teachers,
          rooms: references.rooms,
          defaultBranchId: widget.defaultBranchId,
          decisionCatalogs: references.decisionCatalogs,
          participantLabels: _participantLabels,
          submitLabel: 'Проверить и сохранить',
          onValidate: (reviewRows) => _crm.previewSchedulePlanUpdateConstraints(
            plan.id,
            expectedVersion: plan.version,
            effectiveFrom: _apiDate(effectiveFrom),
            title: plan.title,
            participants: draft.participants,
            activeUntil: plan.activeUntil,
            rows: [
              for (final reviewRow in reviewRows) ..._draftRows(reviewRow),
            ],
          ),
        ),
      );
      if (reviewedRows == null || !mounted) return;
      await _crm.updateSchedulePlan(
        plan.id,
        identity: MagicMutationIdentity.create(
          'schedule-plan-participants-update',
        ),
        expectedVersion: plan.version,
        effectiveFrom: _apiDate(draft.effectiveFrom!),
        title: plan.title,
        participants: draft.participants,
        activeUntil: plan.activeUntil,
        rows: [
          for (final reviewedRow in reviewedRows) ..._draftRows(reviewedRow),
        ],
      );
      await _reload('Участники расписания обновлены');
    } catch (error) {
      _showError('Не удалось обновить участников', error);
    }
  }

  Future<void> _endPlan(SchedulePlan plan) async {
    final changed = await showMagicSheet<bool>(
      context,
      title: 'Завершить «${plan.title}»',
      subtitle: 'Прошедшие и уже рассчитанные занятия сохранятся',
      icon: Icons.stop_circle_outlined,
      builder: (_) => _SchedulePlanEndForm(service: _crm, plan: plan),
    );
    if (changed == true && mounted) await _reload('Расписание завершено');
  }

  Map<String, String> get _participantLabels => {
    if (_groupMode)
      for (final member in widget.groupMembers) member.studentId: member.label,
  };

  PreferredScheduleDraft _draftFromPlanRow(
    SchedulePlanRow row, {
    required DateTime validFrom,
    required DateTime validUntil,
    required String? title,
    required String? subscriptionId,
    required bool openEnded,
  }) => PreferredScheduleDraft(
    seriesId: row.id,
    branchId: row.branchId,
    weekdays: {row.weekday},
    beginTime: row.beginTime,
    durationMinutes: row.durationMinutes,
    lessonsPerDay: 1,
    validFrom: validFrom,
    validUntil: validUntil,
    teacherId: row.teacherId,
    roomId: row.roomId,
    notes: row.notes ?? '',
    title: title,
    subscriptionId: subscriptionId,
    settlementTypeKey:
        row.financialDecision['settlementTypeKey']?.toString() ?? '',
    teacherCompensationRuleKey:
        row.financialDecision['teacherCompensationRuleKey']?.toString() ?? '',
    openEnded: openEnded,
  );

  List<Map<String, dynamic>> _draftRows(PreferredScheduleDraft draft) {
    final rows = <Map<String, dynamic>>[];
    final weekdays = draft.weekdays.toList()..sort();
    for (final weekday in weekdays) {
      for (var slot = 0; slot < draft.lessonsPerDay; slot++) {
        rows.add({
          if (draft.seriesId != null && rows.isEmpty)
            'seriesId': draft.seriesId,
          'teacherId': draft.teacherId,
          'roomId': draft.roomId,
          'branchId': draft.branchId,
          'weekday': weekday,
          'beginTime': _slotTime(draft, slot),
          'durationMinutes': draft.durationMinutes,
          if (draft.notes.isNotEmpty) 'notes': draft.notes,
          'financialDecision': {
            'settlementTypeKey': draft.settlementTypeKey,
            'teacherCompensationRuleKey': draft.teacherCompensationRuleKey,
          },
        });
      }
    }
    return rows;
  }

  String _slotTime(PreferredScheduleDraft draft, int slot) {
    final parts = draft.beginTime.split(':');
    final minutes =
        (int.tryParse(parts.first) ?? 0) * 60 +
        (int.tryParse(parts.last) ?? 0) +
        draft.durationMinutes * slot;
    return '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _reload(String message) async {
    await _controller.load();
    widget.onChanged();
    if (mounted) {
      MagicToast.show(context, message, type: MagicToastType.success);
    }
  }

  void _showError(String message, Object error) {
    if (!mounted) return;
    MagicToast.show(
      context,
      message,
      detail: '$error',
      type: MagicToastType.danger,
    );
  }
}

class _SchedulePlanRowsReview extends ConsumerStatefulWidget {
  const _SchedulePlanRowsReview({
    required this.initialRows,
    required this.branches,
    required this.teachers,
    required this.rooms,
    required this.defaultBranchId,
    required this.decisionCatalogs,
    required this.onValidate,
    this.participantLabels = const {},
    this.submitLabel = 'Проверить и создать',
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
  ConsumerState<_SchedulePlanRowsReview> createState() =>
      _SchedulePlanRowsReviewState();
}

class _SchedulePlanRowsReviewState
    extends ConsumerState<_SchedulePlanRowsReview> {
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
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final issues = _constraintIssues(_preview);
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
          _constraintPanel(issues),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpace.md),
          Text(
            'Не удалось проверить расписание: $_error',
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

  Widget _constraintPanel(List<_PlanConstraintIssue> issues) {
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
          const SizedBox(height: AppSpace.sm),
          for (final issue in issues) ...[
            Text(
              'Строка ${issue.rowIndex + 1}: ${issue.label} · ${issue.dates.take(3).join(', ')}'
              '${issue.dates.length > 3 ? ' и ещё ${issue.dates.length - 3}' : ''}',
            ),
            if (issue.participantLabel != null)
              Text(
                'Участник: ${issue.participantLabel}',
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
                  for (final id in issue.lessonIds)
                    EntityLinkText(
                      text:
                          'Занятие ${id.length <= 8 ? id : id.substring(0, 8)}',
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
        ],
      ),
    );
  }

  List<_PlanConstraintIssue> _constraintIssues(Map<String, dynamic>? preview) {
    if (preview == null) return const [];
    final issues = <String, _PlanConstraintIssue>{};
    for (final rawRow in (preview['rows'] as List? ?? const [])) {
      if (rawRow is! Map) continue;
      final rowIndex = (rawRow['index'] as num?)?.toInt() ?? 0;
      for (final rawFailure in (rawRow['failures'] as List? ?? const [])) {
        if (rawFailure is! Map) continue;
        final studentId = rawFailure['studentId']?.toString() ?? '';
        final occurrence = rawFailure['occurrence'];
        final date = occurrence is Map
            ? occurrence['localDate']?.toString() ?? ''
            : '';
        for (final rawViolation
            in (rawFailure['violations'] as List? ?? const [])) {
          if (rawViolation is! Map) continue;
          final code = rawViolation['code']?.toString() ?? 'UNKNOWN';
          final resource = rawViolation['resource'];
          final resourceId = resource is Map
              ? resource['id']?.toString() ?? ''
              : '';
          final key = '$rowIndex:$code:$resourceId';
          final issue = issues.putIfAbsent(
            key,
            () => _PlanConstraintIssue(
              rowIndex,
              _draftIndexForPreviewRow(rowIndex),
              _constraintLabel(code),
              participantLabel:
                  code == 'CLIENT_OVERLAP' &&
                      widget.participantLabels.isNotEmpty
                  ? widget.participantLabels[studentId] ??
                        'Ученик ${studentId.length <= 8 ? studentId : studentId.substring(0, 8)}'
                  : null,
            ),
          );
          if (date.isNotEmpty) issue.dates.add(date);
          issue.lessonIds.addAll(
            (rawViolation['conflictingLessonIds'] as List? ?? const []).map(
              (id) => id.toString(),
            ),
          );
          issue.rowIndexes.addAll(
            (rawViolation['conflictingRowIndexes'] as List? ?? const [])
                .whereType<num>()
                .map((index) => index.toInt()),
          );
        }
      }
    }
    return issues.values.toList(growable: false);
  }

  int _draftIndexForPreviewRow(int previewRowIndex) {
    var firstRowIndex = 0;
    for (var draftIndex = 0; draftIndex < _rows.length; draftIndex++) {
      final draft = _rows[draftIndex];
      final rowCount = draft.weekdays.length * draft.lessonsPerDay;
      if (previewRowIndex < firstRowIndex + rowCount) return draftIndex;
      firstRowIndex += rowCount;
    }
    return _rows.length - 1;
  }

  String _constraintLabel(String code) => switch (code) {
    'INVALID_INTERVAL' => 'некорректный интервал',
    'OUTSIDE_BRANCH_HOURS' => 'вне часов работы филиала',
    'TEACHER_UNAVAILABLE' => 'педагог недоступен',
    'TEACHER_BRANCH_MISMATCH' => 'педагог не назначен в этот филиал',
    'ROOM_BRANCH_MISMATCH' => 'аудитория относится к другому филиалу',
    'TEACHER_OVERLAP' => 'педагог уже занят',
    'CLIENT_OVERLAP' => 'у клиента уже есть занятие',
    'ROOM_OVERLAP' => 'аудитория уже занята',
    _ => 'нарушено ограничение расписания',
  };
}

class _PlanConstraintIssue {
  _PlanConstraintIssue(
    this.rowIndex,
    this.draftIndex,
    this.label, {
    required this.participantLabel,
  });

  final int rowIndex;
  final int draftIndex;
  final String label;
  final String? participantLabel;
  final Set<String> dates = {};
  final Set<String> lessonIds = {};
  final Set<int> rowIndexes = {};
}

class _SchedulePlanEndForm extends StatefulWidget {
  const _SchedulePlanEndForm({required this.service, required this.plan});

  final MagicCrmService service;
  final SchedulePlan plan;

  @override
  State<_SchedulePlanEndForm> createState() => _SchedulePlanEndFormState();
}

class _SchedulePlanEndFormState extends State<_SchedulePlanEndForm> {
  late final TextEditingController _reason;
  late DateTime _lastDate;
  SchedulePlanEndPreview? _preview;
  MagicMutationIdentity? _identity;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reason = TextEditingController();
    final today = DateUtils.dateOnly(DateTime.now());
    final starts = DateTime.tryParse(widget.plan.activeFrom) ?? today;
    _lastDate = starts.isAfter(today) ? starts : today;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final starts = DateTime.tryParse(widget.plan.activeFrom) ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastDate,
      firstDate: starts.isAfter(today) ? starts : today,
      lastDate: DateUtils.dateOnly(
        DateTime.now().add(const Duration(days: 730)),
      ),
    );
    if (picked != null) _invalidate(() => _lastDate = picked);
  }

  void _invalidate(VoidCallback change) {
    setState(() {
      change();
      _preview = null;
      _identity = null;
      _error = null;
    });
  }

  Future<void> _calculate() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Укажите причину завершения.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await widget.service.previewSchedulePlanEnd(
        widget.plan.id,
        expectedVersion: widget.plan.version,
        lastDate: _apiDate(_lastDate),
        reasonText: reason,
      );
      if (mounted) setState(() => _preview = preview);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _commit() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.service.endSchedulePlan(
        widget.plan.id,
        identity: _identity ??= MagicMutationIdentity.create(
          'schedule-plan-end',
        ),
        expectedVersion: widget.plan.version,
        lastDate: _apiDate(_lastDate),
        reasonText: _reason.text,
        previewToken: preview.previewToken,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final impact = _preview?.impact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const Key('schedule-plan-end-date'),
          onTap: _loading ? null : _pickDate,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Последняя дата'),
            child: Text(DateFormat('dd.MM.yyyy').format(_lastDate)),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          key: const Key('schedule-plan-end-reason'),
          controller: _reason,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Причина',
            hintText: 'Причина будет видна сотрудникам в истории',
          ),
          onChanged: (_) => _invalidate(() {}),
        ),
        if (impact != null) ...[
          Container(
            key: const Key('schedule-plan-end-impact'),
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: AppColor.warning.withValues(alpha: 0.12),
              border: Border.all(color: AppColor.warning),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Text(
              'Будут отменены: ${impact['futureUnsettledLessons'] ?? 0}\n'
              'Освободятся резервы: ${impact['activeReservations'] ?? 0} '
              '(${impact['reservedUnits'] ?? '0.00'} ч)\n'
              'Сохранятся завершённые: ${impact['preservedTerminalLessons'] ?? 0}',
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (_loading) const LinearProgressIndicator(color: AppColor.gold),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _loading
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: FilledButton(
                key: const Key('schedule-plan-end-submit'),
                onPressed: _loading
                    ? null
                    : (_preview == null ? _calculate : _commit),
                style: _preview == null
                    ? null
                    : FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                child: Text(_preview == null ? 'Рассчитать' : 'Завершить'),
              ),
            ),
          ],
        ),
      ],
    );
  }
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
    return SizedBox(
      key: const Key('client-lesson-date-tray'),
      height: 84,
      child: GridView.builder(
        key: PageStorageKey('client-lesson-date-tray-$storageKey'),
        scrollDirection: Axis.horizontal,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 78,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) =>
            _TrayTile(item: items[index], onTap: () => onOpen(items[index])),
      ),
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
    final accent = state.token.accent;
    final markerAccent = marker == null
        ? accent
        : _settlementColor(marker['colorToken']?.toString());
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
            color: accent.withValues(alpha: 0.12),
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
                    Icon(_stateIcon(item.state), size: 10, color: accent),
                  ],
                ),
              ),
              if (marker != null)
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

String _apiDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

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

Color _settlementColor(String? token) => switch (token) {
  'success' => AppColor.success,
  'warning' => AppColor.warning,
  'info' || 'blue' || 'cyan' => AppColor.actionBlue,
  'violet' => const Color(0xFF7C5CBF),
  _ => AppColor.text2,
};
