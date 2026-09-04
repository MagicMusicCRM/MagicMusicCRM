import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/navigation/crm_nav_rbac.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';
import 'package:magic_music_crm/core/widgets/magic_toast.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'group_schedule_participants_editor.dart';
import 'recurring_schedule_plan_controller.dart';
import 'recurring_schedule_plan_view.dart';
import 'schedule_plan_mutation_flow.dart';
import 'schedule_plan_row_removal_flow.dart';

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

  SchedulePlanMutationFlow get _mutationFlow => SchedulePlanMutationFlow(
    service: _crm,
    api: ref.read(magicApiClientProvider),
    branches: widget.branches,
    subscriptions: widget.subscriptions,
    groupMembers: widget.groupMembers,
    studentId: widget.studentId,
    groupId: widget.groupId,
    subjectName: widget.subjectName,
    defaultBranchId: widget.defaultBranchId,
    canManageTeacherCompensation: _canManageTeacherCompensation,
  );

  bool get _canManageTeacherCompensation {
    final snapshot = ref.read(capabilitySnapshotProvider).asData?.value;
    return snapshot != null && crmCanManageTeacherRates(snapshot);
  }

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
        timelinePage: _controller.timelinePage,
        timelineLoading: _controller.timelineLoading,
        timelinePaging: _controller.timelinePaging,
        timelineError: _controller.timelineError,
        onCreate: _createPlan,
        onRetryPlans: _controller.load,
        onPreviousTimeline: _controller.previousTimeline,
        onNextTimeline: _controller.nextTimeline,
        onRetryTimeline: _controller.retryTimeline,
        onEditPlan: (plan, row) => _editPlan(plan, row: row),
        onRemoveRow: _removeRow,
        onEditParticipants: _editParticipants,
        onEndPlan: _endPlan,
        onOpenTimelineItem: _openTimelineItem,
        emptyState: const MagicPageState(
          kind: MagicPageStateKind.empty,
          title: 'Постоянных расписаний пока нет',
          message: 'Разовые и ранее созданные занятия всё равно показаны ниже.',
        ),
        onOpenFallbackLesson: widget.onOpenLesson,
      ),
    );
  }

  Future<void> _openTimelineItem(String lessonId) async {
    try {
      final exact = await _crm.listLessons(lessonId: lessonId, limit: 1);
      final lesson = exact.firstOrNull;
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

  Future<void> _createPlan() => _runMutation(
    operation: () => _mutationFlow.create(context),
    successMessage: 'Расписание создано',
    errorMessage: 'Не удалось создать расписание',
  );

  Future<void> _editPlan(SchedulePlan plan, {SchedulePlanRow? row}) =>
      _runMutation(
        operation: () => _mutationFlow.edit(context, plan, row: row),
        successMessage: 'Расписание обновлено',
        errorMessage: 'Не удалось обновить расписание',
      );

  Future<void> _editParticipants(SchedulePlan plan) => _runMutation(
    operation: () => _mutationFlow.editParticipants(context, plan),
    successMessage: 'Участники расписания обновлены',
    errorMessage: 'Не удалось обновить участников',
  );

  Future<void> _endPlan(SchedulePlan plan) => _runMutation(
    operation: () => _mutationFlow.end(context, plan),
    successMessage: 'Расписание завершено',
    errorMessage: 'Не удалось завершить расписание',
  );

  Future<void> _removeRow(SchedulePlan plan, SchedulePlanRow row) async {
    try {
      final removed = await SchedulePlanRowRemovalFlow(
        service: _crm,
        onInvalidated: _controller.load,
      ).remove(context, plan: plan, row: row);
      if (removed && mounted) {
        await _reload('Строка расписания удалена');
      }
    } catch (error) {
      _showError('Не удалось удалить строку расписания', error);
    }
  }

  Future<void> _runMutation({
    required Future<SchedulePlanMutationResult> Function() operation,
    required String successMessage,
    required String errorMessage,
  }) async {
    try {
      final result = await operation();
      if (result == SchedulePlanMutationResult.committed && mounted) {
        await _reload(successMessage);
      }
    } catch (error) {
      _showError(errorMessage, error);
    }
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
