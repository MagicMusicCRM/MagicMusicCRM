import 'dart:async';

import 'package:magic_music_crm/core/widgets/magic_picker.dart';
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
    this.canManageTeacherCompensation = false,
    this.initialClientDecisions = const [],
    this.participantLabels = const {},
    this.teacherAvailable,
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
  final bool canManageTeacherCompensation;
  final List<Map<String, dynamic>> initialClientDecisions;
  final Map<String, String> participantLabels;
  final Future<bool> Function(PreferredScheduleDraft draft)? teacherAvailable;

  @override
  State<PreferredScheduleEditor> createState() =>
      _PreferredScheduleEditorState();
}

class _PreferredScheduleEditorState extends State<PreferredScheduleEditor> {
  late final PreferredScheduleEditorController _controller;
  late final DirtyFormExitController _exitController;
  late final TextEditingController _notesController;
  late final TextEditingController _titleController;
  Set<String> _availableTeacherIds = {};
  bool _teacherOptionsLoading = false;
  String? _teacherOptionsError;
  String? _teacherOptionsKey;
  int _teacherOptionsGeneration = 0;
  Timer? _teacherOptionsTimer;
  Future<void>? _teacherOptionsPending;

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
      canManageTeacherCompensation: widget.canManageTeacherCompensation,
      initialClientDecisions: widget.initialClientDecisions,
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
    unawaited(_refreshTeacherOptions());
  }

  @override
  void dispose() {
    _teacherOptionsTimer?.cancel();
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
    _teacherOptionsTimer?.cancel();
    _teacherOptionsTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) unawaited(_refreshTeacherOptions());
    });
  }

  Future<void> _refreshTeacherOptions({bool force = false}) async {
    final check = widget.teacherAvailable;
    if (check == null) return;
    final draft = _draft;
    final candidates = _controller.teachersForBranch;
    final roomId = draft.roomId.isNotEmpty
        ? draft.roomId
        : (_controller.roomsForBranch.firstOrNull?['id']?.toString() ?? '');
    final rangeMissesDay =
        !draft.openEnded &&
        draft.weekdays.any(
          (day) => draft.validFrom
              .add(Duration(days: (day - draft.validFrom.weekday + 7) % 7))
              .isAfter(draft.validUntil),
        );
    if (roomId.isEmpty ||
        draft.weekdays.isEmpty ||
        rangeMissesDay ||
        (draft.teacherCompensationSource == 'manual' &&
            draft.plannedSettlementReason.isEmpty)) {
      ++_teacherOptionsGeneration;
      setState(() {
        _availableTeacherIds = {};
        _teacherOptionsLoading = false;
        _teacherOptionsError = null;
        _teacherOptionsKey = null;
      });
      return;
    }
    final key = [
      draft.branchId,
      roomId,
      (draft.weekdays.toList()..sort()).join(','),
      draft.beginTime,
      draft.durationMinutes,
      draft.lessonsPerDay,
      draft.validFrom.toIso8601String(),
      draft.openEnded ? '' : draft.validUntil.toIso8601String(),
      draft.subscriptionId,
      draft.settlementTypeKey,
      draft.teacherCompensationRuleKey,
      draft.teacherCreditedDurationMinutes,
      draft.clientDecisions.toString(),
      candidates.map((teacher) => teacher['id']).join(','),
    ].join('|');
    if (!force &&
        _teacherOptionsKey == key &&
        (_teacherOptionsLoading || _teacherOptionsError == null)) {
      return;
    }
    final generation = ++_teacherOptionsGeneration;
    setState(() {
      _teacherOptionsKey = key;
      _availableTeacherIds = {};
      _teacherOptionsLoading = true;
      _teacherOptionsError = null;
    });
    final previous = _teacherOptionsPending;
    final completion = Completer<void>();
    _teacherOptionsPending = completion.future;
    try {
      await previous;
      if (!mounted || generation != _teacherOptionsGeneration) return;
      final available = <String>{};
      // ponytail: four concurrent plan previews cap DB work; batch if branches regularly exceed 100 teachers.
      for (var index = 0; index < candidates.length; index += 4) {
        final chunk = candidates.skip(index).take(4).toList();
        final results = await Future.wait([
          for (final teacher in chunk)
            check(
              draft.copyWith(
                teacherId: teacher['id'].toString(),
                roomId: roomId,
              ),
            ),
        ]);
        if (!mounted || generation != _teacherOptionsGeneration) return;
        for (var i = 0; i < chunk.length; i++) {
          if (results[i]) available.add(chunk[i]['id'].toString());
        }
      }
      if (!mounted || generation != _teacherOptionsGeneration) return;
      setState(() {
        _availableTeacherIds = available;
        _teacherOptionsLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _teacherOptionsGeneration) return;
      setState(() {
        _teacherOptionsError = 'Не удалось проверить доступность педагогов.';
        _teacherOptionsLoading = false;
      });
    } finally {
      completion.complete();
    }
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
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showMagicDatePicker(
      context: context,
      initialDate: start ? state.validFrom : state.validUntil,
      firstDate: start
          ? (widget.planMode ? DateTime(1900) : today)
          : state.validFrom,
      lastDate: DateUtils.dateOnly(today.add(const Duration(days: 730))),
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
    final picked = await showMagicTimePicker(
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
      teachers: widget.teacherAvailable == null
          ? _controller.teachersForBranch
          : _controller.teachersForBranch
                .where(
                  (teacher) =>
                      _availableTeacherIds.contains(teacher['id']?.toString()),
                )
                .toList(),
      selectedTeacherLabel: _controller.teachersForBranch
          .where(
            (teacher) =>
                teacher['id']?.toString() == _controller.state.teacherId,
          )
          .map(
            (teacher) =>
                '${teacher['first_name'] ?? ''} ${teacher['last_name'] ?? ''}'
                    .trim(),
          )
          .firstOrNull,
      teacherOptionsLoading: _teacherOptionsLoading,
      teacherOptionsError: _teacherOptionsError,
      onTeacherOptionsRetry: () =>
          unawaited(_refreshTeacherOptions(force: true)),
      rooms: _controller.roomsForBranch,
      decisionCatalog: _controller.decisionCatalog,
      titleController: _titleController,
      notesController: _notesController,
      isEdit: _controller.isEdit,
      planMode: widget.planMode,
      requireFinancialDecision: widget.requireFinancialDecision,
      canManageTeacherCompensation: widget.canManageTeacherCompensation,
      participantLabels: widget.participantLabels,
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
      onPlannedSettlementReasonChanged: (value) =>
          _changed(() => _controller.setPlannedSettlementReason(value)),
      onTeacherMinutesChanged: (value) =>
          _changed(() => _controller.setTeacherCreditedDurationInput(value)),
      onClientMinutesChanged: (clientId, value) => _changed(
        () => _controller.setClientChargeDurationInput(clientId, value),
      ),
      onApplyRecommendation: () =>
          _changed(_controller.applyRecommendedTeacherCompensation),
      onPickStartDate: () => _pickDate(start: true),
      onPickEndDate: () => _pickDate(start: false),
      onOpenEndedChanged: (value) =>
          _changed(() => _controller.setOpenEnded(value)),
      onCancel: _cancel,
      onSubmit: _submit,
    ),
  );
}
