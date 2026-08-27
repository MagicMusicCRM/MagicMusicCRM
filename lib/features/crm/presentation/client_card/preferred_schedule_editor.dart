import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/forms/dirty_form_exit.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';

import 'preferred_schedule_draft.dart';
import 'preferred_schedule_editor_controller.dart';
import 'preferred_schedule_editor_view.dart';

export 'preferred_schedule_draft.dart';

class PreferredScheduleEditor extends StatefulWidget {
  const PreferredScheduleEditor({
    required this.branches,
    required this.teachers,
    required this.rooms,
    required this.defaultBranchId,
    this.series,
    this.planMode = false,
    this.initialTitle,
    this.initialDraft,
    this.subscriptionOptions = const [],
    this.initialSubscriptionId,
    this.requireSubscription = false,
    this.allowOpenEnded = false,
    this.showPeriod = true,
    this.decisionCatalogs = const {},
    this.requireFinancialDecision = false,
    super.key,
  });

  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> rooms;
  final String? defaultBranchId;
  final Map<String, dynamic>? series;
  final bool planMode;
  final String? initialTitle;
  final PreferredScheduleDraft? initialDraft;
  final List<Map<String, dynamic>> subscriptionOptions;
  final String? initialSubscriptionId;
  final bool requireSubscription;
  final bool allowOpenEnded;
  final bool showPeriod;
  final Map<String, LessonDecisionCatalog> decisionCatalogs;
  final bool requireFinancialDecision;

  @override
  State<PreferredScheduleEditor> createState() =>
      _PreferredScheduleEditorState();
}

class _PreferredScheduleEditorState extends State<PreferredScheduleEditor> {
  late final PreferredScheduleEditorController _controller;
  late final DirtyFormExitController _exitController;
  late final TextEditingController _notesController;
  late final TextEditingController _titleController;

  PreferredScheduleDraft get _draft => _controller.buildDraft(
    title: _titleController.text,
    notes: _notesController.text,
  );

  @override
  void initState() {
    super.initState();
    _controller = PreferredScheduleEditorController(
      branches: widget.branches,
      teachers: widget.teachers,
      rooms: widget.rooms,
      defaultBranchId: widget.defaultBranchId,
      series: widget.series,
      planMode: widget.planMode,
      initialDraft: widget.initialDraft,
      subscriptionOptions: widget.subscriptionOptions,
      initialSubscriptionId: widget.initialSubscriptionId,
      requireSubscription: widget.requireSubscription,
      allowOpenEnded: widget.allowOpenEnded,
      decisionCatalogs: widget.decisionCatalogs,
      requireFinancialDecision: widget.requireFinancialDecision,
    )..initialize();
    _controller.addListener(_refresh);
    _notesController = TextEditingController(
      text:
          widget.series?['notes']?.toString() ??
          widget.initialDraft?.notes ??
          '',
    );
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _exitController = DirtyFormExitController(onSave: _validate);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    _exitController.dispose();
    _notesController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _changed(VoidCallback change) {
    change();
    _exitController.markDirty();
  }

  void _textChanged() => _changed(_controller.clearValidationError);

  Future<bool> _validate() async =>
      _controller.validate(title: _titleController.text);

  Future<void> _submit() async {
    if (!await _validate() || !mounted) return;
    _exitController.markClean();
    Navigator.of(context).pop(_draft);
  }

  Future<void> _cancel() => _exitController.requestExit(
    context,
    reason: DirtyFormExitReason.appBack,
    savedResult: _draft,
  );

  Future<void> _pickDate({required bool start}) async {
    final state = _controller.state;
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? state.validFrom : state.validUntil,
      firstDate: start ? DateUtils.dateOnly(DateTime.now()) : state.validFrom,
      lastDate: DateUtils.dateOnly(
        DateTime.now().add(const Duration(days: 730)),
      ),
    );
    if (picked == null || !mounted) return;
    _changed(
      () => start
          ? _controller.setValidFrom(picked)
          : _controller.setValidUntil(picked),
    );
  }

  Future<void> _pickTime() async {
    final parts = _controller.state.beginTime.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 15,
        minute: int.tryParse(parts.last) ?? 0,
      ),
    );
    if (picked == null || !mounted) return;
    _changed(
      () => _controller.setBeginTime(
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DirtyFormExitScope(
    controller: _exitController,
    savedResult: _draft,
    child: PreferredScheduleEditorView(
      state: _controller.state,
      branches: widget.branches,
      subscriptionOptions: widget.subscriptionOptions,
      teachers: _controller.teachersForBranch,
      rooms: _controller.roomsForBranch,
      decisionCatalog: _controller.decisionCatalog,
      titleController: _titleController,
      notesController: _notesController,
      isEdit: _controller.isEdit,
      planMode: widget.planMode,
      requireFinancialDecision: widget.requireFinancialDecision,
      requireSubscription: widget.requireSubscription,
      allowOpenEnded: widget.allowOpenEnded,
      showPeriod: widget.showPeriod,
      onTextChanged: _textChanged,
      onBranchChanged: (value) =>
          _changed(() => _controller.selectBranch(value)),
      onWeekdayChanged: (day, selected) =>
          _changed(() => _controller.toggleWeekday(day, selected)),
      onPickTime: _pickTime,
      onDurationChanged: (value) =>
          _changed(() => _controller.selectDurationMinutes(value)),
      onLessonsPerDayChanged: (value) =>
          _changed(() => _controller.selectLessonsPerDay(value)),
      onTeacherChanged: (value) =>
          _changed(() => _controller.selectTeacher(value)),
      onRoomChanged: (value) => _changed(() => _controller.selectRoom(value)),
      onSubscriptionChanged: (value) =>
          _changed(() => _controller.selectSubscription(value)),
      onSettlementTypeChanged: (value) =>
          _changed(() => _controller.selectSettlementType(value)),
      onCompensationRuleChanged: (value) =>
          _changed(() => _controller.selectTeacherCompensationRule(value)),
      onPickStartDate: () => _pickDate(start: true),
      onPickEndDate: () => _pickDate(start: false),
      onOpenEndedChanged: (value) =>
          _changed(() => _controller.setOpenEnded(value)),
      onCancel: _cancel,
      onSubmit: _submit,
    ),
  );
}
