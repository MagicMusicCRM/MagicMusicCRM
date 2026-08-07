import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

import 'preferred_schedule_editor.dart';
import 'recurring_schedule_plan_controller.dart';

class RecurringSchedulePlanSection extends ConsumerStatefulWidget {
  const RecurringSchedulePlanSection({
    super.key,
    required this.studentId,
    required this.fallbackLessons,
    required this.branches,
    required this.defaultBranchId,
    required this.subscriptions,
    required this.canWrite,
    required this.onChanged,
    this.onOpenLesson,
  });

  final String studentId;
  final List<Map<String, dynamic>> fallbackLessons;
  final List<Map<String, dynamic>> branches;
  final String? defaultBranchId;
  final List<Map<String, dynamic>> subscriptions;
  final bool canWrite;
  final VoidCallback onChanged;
  final ValueChanged<Map<String, dynamic>>? onOpenLesson;

  @override
  ConsumerState<RecurringSchedulePlanSection> createState() =>
      _RecurringSchedulePlanSectionState();
}

class _RecurringSchedulePlanSectionState
    extends ConsumerState<RecurringSchedulePlanSection> {
  late RecurringSchedulePlanController _controller;

  MagicCrmService get _crm => ref.read(magicCrmServiceProvider);

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant RecurringSchedulePlanSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId) {
      _controller.dispose();
      _createController();
    }
  }

  void _createController() {
    _controller = RecurringSchedulePlanController(
      service: _crm,
      studentId: widget.studentId,
    )..load();
  }

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
                            onPressed: widget.subscriptions.isEmpty
                                ? null
                                : _createPlan,
                            tooltip: 'Добавить расписание',
                            icon: const Icon(Icons.add_rounded),
                          )
                        : TextButton.icon(
                            key: const Key('schedule-plan-add'),
                            onPressed: widget.subscriptions.isEmpty
                                ? null
                                : _createPlan,
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: const Text('Добавить расписание'),
                          ),
                ],
              ),
            ),
            if (widget.canWrite && widget.subscriptions.isEmpty)
              Text(
                'Для нового индивидуального расписания нужен активный абонемент.',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Лента занятий',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed:
                  page.hasPrevious &&
                      !_controller.loadingTrays.contains(plan.id)
                  ? () => _controller.pageTray(plan, 'previous')
                  : null,
              tooltip: 'Предыдущие занятия',
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
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
            items: page.items,
            onOpen: _openTrayItem,
          ),
        if (_controller.loadingTrays.contains(plan.id))
          const LinearProgressIndicator(color: AppColor.gold),
      ],
    );
  }

  void _openTrayItem(SchedulePlanTrayItem item) {
    final lesson = widget.fallbackLessons
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (candidate) => candidate?['id']?.toString() == item.id,
          orElse: () => null,
        );
    if (lesson != null) widget.onOpenLesson?.call(lesson);
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
    ({List<Map<String, dynamic>> teachers, List<Map<String, dynamic>> rooms})
  >
  _references() async {
    final values = await Future.wait([
      _crm.listTeachers(limit: 100),
      _crm.listRooms(limit: 100),
    ]);
    return (
      teachers: List<Map<String, dynamic>>.from(values[0]),
      rooms: List<Map<String, dynamic>>.from(values[1]),
    );
  }

  Future<void> _createPlan() async {
    try {
      final references = await _references();
      if (!mounted) return;
      final draft = await showMagicSheet<PreferredScheduleDraft>(
        context,
        title: 'Новое постоянное расписание',
        subtitle: 'Можно создать несколько дней и занятий одной командой',
        icon: Icons.event_repeat_rounded,
        builder: (_) => PreferredScheduleEditor(
          planMode: true,
          initialTitle: 'Индивидуальные занятия',
          subscriptionOptions: widget.subscriptions,
          initialSubscriptionId: widget.subscriptions.first['id']?.toString(),
          requireSubscription: true,
          allowOpenEnded: true,
          branches: widget.branches,
          teachers: references.teachers,
          rooms: references.rooms,
          defaultBranchId: widget.defaultBranchId,
        ),
      );
      if (draft == null || !mounted) return;
      await _crm.createSchedulePlan(
        identity: MagicMutationIdentity.create('schedule-plan-create'),
        title: draft.title!,
        studentId: widget.studentId,
        subscriptionId: draft.subscriptionId!,
        activeFrom: _apiDate(draft.validFrom),
        activeUntil: draft.openEnded ? null : _apiDate(draft.validUntil),
        rows: _draftRows(draft),
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
        ),
      );
      if (draft == null || !mounted) return;
      final rows = plan.currentRows.map((item) => item.command()).toList();
      final additions = _draftRows(draft);
      if (row == null) {
        rows.addAll(additions);
      } else {
        final index = rows.indexWhere((item) => item['seriesId'] == row.id);
        rows[index] = {...additions.single, 'seriesId': row.id};
      }
      await _crm.updateSchedulePlan(
        plan.id,
        identity: MagicMutationIdentity.create('schedule-plan-update'),
        expectedVersion: plan.version,
        effectiveFrom: _apiDate(draft.validFrom),
        title: draft.title!,
        subscriptionId: plan.isGroup ? null : draft.subscriptionId,
        activeUntil: draft.openEnded ? null : _apiDate(draft.validUntil),
        rows: rows,
      );
      await _reload('Расписание обновлено');
    } catch (error) {
      _showError('Не удалось обновить расписание', error);
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

  List<Map<String, dynamic>> _draftRows(PreferredScheduleDraft draft) {
    final rows = <Map<String, dynamic>>[];
    final weekdays = draft.weekdays.toList()..sort();
    for (final weekday in weekdays) {
      for (var slot = 0; slot < draft.lessonsPerDay; slot++) {
        rows.add({
          'teacherId': draft.teacherId,
          'roomId': draft.roomId,
          'branchId': draft.branchId,
          'weekday': weekday,
          'beginTime': _slotTime(draft, slot),
          'durationMinutes': draft.durationMinutes,
          if (draft.notes.isNotEmpty) 'notes': draft.notes,
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
  const _LessonTrayGrid({super.key, required this.items, required this.onOpen});

  final List<SchedulePlanTrayItem> items;
  final ValueChanged<SchedulePlanTrayItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: GridView.builder(
        key: const Key('client-lesson-date-tray'),
        scrollDirection: Axis.horizontal,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 58,
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
    final accent = marker == null
        ? state.token.accent
        : _settlementColor(marker['colorToken']?.toString());
    final markerLabels = item.settlementMarkers
        .map((value) => value['label']?.toString())
        .whereType<String>();
    final tooltip = [
      '${_date(item.localDate)} ${item.localTime}',
      state.label,
      ...markerLabels,
      if (item.teacherName != null) item.teacherName!,
      if (item.roomName != null) item.roomName!,
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
                      _shortDate(item.localDate),
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
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
                  child: Icon(Icons.sell_outlined, size: 9, color: accent),
                ),
              if (item.relationMarker != 'none')
                Positioned(
                  bottom: 1,
                  left: 2,
                  child: Icon(Icons.call_split_rounded, size: 9, color: accent),
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

String _shortDate(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null ? value : DateFormat('d.MM').format(parsed);
}

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
