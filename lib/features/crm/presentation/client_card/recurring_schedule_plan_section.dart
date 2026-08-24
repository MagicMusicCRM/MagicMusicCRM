import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';
import 'package:magic_music_crm/core/widgets/magic_toast.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision_flow.dart';
import 'preferred_schedule_editor.dart';
import 'group_schedule_participants_editor.dart';
import 'recurring_schedule_plan_controller.dart';
import 'recurring_schedule_plan_view.dart';
import 'schedule_plan_rows_review.dart';

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
      builder: (context, _) => RecurringSchedulePlanView(
        plans: _controller.plans,
        loading: _controller.loading,
        error: _controller.error,
        canWrite: widget.canWrite,
        canCreatePlan: _canCreatePlan,
        groupMode: _groupMode,
        hasGroupMembers: widget.groupMembers.isNotEmpty,
        fallbackLessons: widget.fallbackLessons,
        trays: _controller.trays,
        loadingTrayIds: _controller.loadingTrays,
        trayErrors: _controller.trayErrors,
        onCreate: _createPlan,
        onRetryPlans: _controller.load,
        onEnsureTray: _controller.ensureTray,
        onPageTray: _controller.pageTray,
        onRetryTray: _controller.retryTray,
        onEditPlan: (plan, row) => _editPlan(plan, row: row),
        onEditParticipants: _editParticipants,
        onEndPlan: _endPlan,
        onOpenTrayItem: _openTrayItem,
        emptyState: const MagicPageState(
          kind: MagicPageStateKind.empty,
          title: 'Постоянных расписаний пока нет',
          message: 'Разовые и ранее созданные занятия всё равно показаны ниже.',
        ),
        onOpenFallbackLesson: widget.onOpenLesson,
      ),
    );
  }

  Future<void> _openTrayItem(SchedulePlanTrayItem item) async {
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
    }
  }

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
        builder: (_) => SchedulePlanRowsReview(
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
        builder: (_) => SchedulePlanRowsReview(
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
        builder: (_) => SchedulePlanRowsReview(
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
      detail: userErrorMessage(error, fallback: '$message.'),
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
      if (mounted) {
        setState(
          () => _error = userErrorMessage(
            error,
            fallback: 'Не удалось рассчитать завершение расписания.',
          ),
        );
      }
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
      if (mounted) {
        setState(
          () => _error = userErrorMessage(
            error,
            fallback: 'Не удалось завершить расписание.',
          ),
        );
      }
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

String _apiDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
