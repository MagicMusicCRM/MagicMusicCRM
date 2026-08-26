import 'dart:async';
// ignore_for_file: annotate_overrides
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/features/admin/presentation/providers/schedule_navigation_provider.dart';
import 'lesson_decision_flow.dart';
import 'lesson_editor/lesson_editor_data_controller.dart';
import 'lesson_editor/lesson_editor_decision_policy.dart';
import 'lesson_editor/lesson_editor_initial_mapper.dart';
import 'lesson_editor/lesson_editor_models.dart';
import 'lesson_editor/lesson_editor_save_flow.dart';
import 'lesson_editor/lesson_editor_schedule_controller.dart';
import 'lesson_editor/lesson_editor_view.dart';

class CreateLessonDialog extends ConsumerStatefulWidget
    implements LessonEditorInitialSource {
  final DateTime? initialDate;
  final String? initialRoomId, initialBranchId, leadId, leadName;
  final String? clientType, clientId, clientName;
  final int? initialDurationMinutes;
  final Map<String, dynamic>? lesson;
  final bool initialIsTrial, pageMode;
  const CreateLessonDialog({
    super.key,
    this.initialDate,
    this.initialRoomId,
    this.initialBranchId,
    this.initialDurationMinutes,
    this.lesson,
    this.leadId,
    this.leadName,
    this.clientType,
    this.clientId,
    this.clientName,
    this.initialIsTrial = false,
    this.pageMode = false,
  });
  static Future<bool?> show(
    BuildContext context, {
    DateTime? initialDate,
    String? initialRoomId,
    String? initialBranchId,
    int? initialDurationMinutes,
    Map<String, dynamic>? lesson,
    String? leadId,
    String? leadName,
    String? clientType,
    String? clientId,
    String? clientName,
    bool initialIsTrial = false,
  }) {
    CreateLessonDialog editor(bool pageMode) => CreateLessonDialog(
      initialDate: initialDate,
      initialRoomId: initialRoomId,
      initialBranchId: initialBranchId,
      initialDurationMinutes: initialDurationMinutes,
      lesson: lesson,
      leadId: leadId,
      leadName: leadName,
      clientType: clientType,
      clientId: clientId,
      clientName: clientName,
      initialIsTrial: initialIsTrial,
      pageMode: pageMode,
    );
    if (WorkspaceNavigationScope.maybeOf(context)?.isDesktop == true) {
      return showDialog<bool>(context: context, builder: (_) => editor(false));
    }
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        settings: const RouteSettings(name: 'lesson-editor'),
        builder: (_) => editor(true),
      ),
    );
  }

  createState() => _LessonEditorDialogState();
}

class _LessonEditorDialogState extends ConsumerState<CreateLessonDialog>
    implements LessonEditorActions {
  static const _policy = LessonEditorDecisionPolicy();
  final _scroll = ScrollController(keepScrollOffset: false);
  late LessonEditorSession _session;
  late LessonEditorDraft _draft;
  var _refs = const LessonEditorReferenceState.empty();
  late final LessonEditorDataController _data;
  late final LessonEditorScheduleController _schedule;
  late final LessonEditorSaveFlow _flow;
  (bool loading, String? error) _loadState = (true, null);
  (bool analyzing, String? error) _scheduleState = (false, null);
  bool _saving = false;
  LessonEditorValidation _valid = const LessonEditorValidation.valid();
  LessonScheduleAnalysis? _conflicts;
  void initState() {
    super.initState();
    _session = const LessonEditorInitialMapper().fromSource(widget);
    _draft = _session.draft;
    final crm = ref.read(magicCrmServiceProvider);
    _data = LessonEditorDataController.fromCrm(crm);
    _schedule = LessonEditorScheduleController.fromCrm(crm, policy: _policy);
    _flow = LessonEditorSaveFlow.fromCrm(crm);
    unawaited(_refreshReferences());
  }

  void dispose() {
    _data.invalidateClientSelection();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refreshReferences() async {
    _data.invalidateClientSelection();
    setState(() => _loadState = (true, null));
    final result = await _data.loadInitialSafely(_session);
    if (!mounted) return;
    if (result.patch case final patch?) {
      return _acceptPatch(patch, loaded: true);
    }
    setState(() => _loadState = (false, lessonLoadErrorMessage(result.error)));
  }

  void _acceptPatch(LessonEditorLoadPatch patch, {bool loaded = false}) {
    final references = patch.references;
    final defaults = _policy.applyReferenceDefaults(
      _session,
      patch.draft ?? _draft,
      references,
      patch.appliesCatalogDefaults && (widget.initialDurationMinutes ?? 0) <= 0,
    );
    setState(() {
      _session = defaults.session;
      _draft = defaults.draft;
      _refs = references;
      if (loaded) _loadState = (false, _loadState.$2);
    });
  }

  void _updateDraft(LessonEditorDraft value, {bool scheduleChanged = false}) {
    setState(() {
      _draft = value;
      if (!scheduleChanged) return;
      _conflicts = null;
      _scheduleState = (_scheduleState.$1, null);
    });
  }

  Widget build(BuildContext context) => LessonEditorView.fromState(
    (_session, _draft, _refs),
    (_conflicts, _loadState.$1, _saving, _scheduleState.$1),
    (_valid.message, _loadState.$2, _scheduleState.$2),
    actions: this,
    pageMode: widget.pageMode,
    title: lessonEditorTitle(_session, widget.leadId != null),
    scrollController: _scroll,
    onRetry: _refreshReferences,
  );
  searchClients(String q) => _data.searchClients(q);
  void selectClient(LessonClientRef? value) => unawaited(
    _requestPatch(
      _data.selectClient(value, draft: _draft, references: _refs),
      'Не удалось выбрать клиента.',
    ),
  );
  void edit(LessonEditorEdit edit) {
    final change = _policy.applyEdit(_draft, _refs, edit);
    _updateDraft(change.draft, scheduleChanged: change.scheduleChanged);
    if (change.branchToLoad case final branchId?) {
      unawaited(
        _requestPatch(
          _data.loadBranch(branchId, draft: _draft, references: _refs),
          'Не удалось загрузить данные филиала.',
        ),
      );
    }
  }

  Future<void> selectDate(LessonDatePickerRequest request) async {
    final date = await showDatePicker(
      context: context,
      initialDate: request.initialDate,
      firstDate: request.firstDate,
      lastDate: request.lastDate,
    );
    if (!mounted || date == null) return;
    _updateDraft(_draft.withDate(date), scheduleChanged: true);
  }

  Future<void> selectTime(LessonTimePickerRequest request) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: request.hour, minute: request.minute),
      builder: lessonTimePicker24HourBuilder,
    );
    if (!mounted || time == null) return;
    _updateDraft(
      _draft.withTime(time.hour, time.minute),
      scheduleChanged: true,
    );
  }

  Future<void> applySuggestion(ScheduleSuggestion value) async {
    final draft = _schedule.applySuggestion(_draft, value);
    _updateDraft(draft, scheduleChanged: true);
    await analyzeSchedule();
  }

  void openConstraint(LessonConstraintViolation value) {
    if (value.conflictingLessonIds.firstOrNull case final lessonId?) {
      _focusConstraint(lessonId);
    }
  }

  Future<void> _requestPatch(
    Future<LessonEditorLoadPatch?> request,
    String fallback,
  ) async {
    try {
      final patch = await request;
      if (mounted && patch != null) _acceptPatch(patch);
    } catch (error) {
      if (mounted) _showError(error, fallback);
    }
  }

  Future<void> analyzeSchedule() async {
    setState(() => _scheduleState = (true, null));
    final result = await _schedule.inspect(_session, _draft);
    if (!mounted) return;
    setState(() {
      _conflicts = result.analysis;
      _scheduleState = (false, lessonScheduleErrorMessage(result.error));
    });
  }

  Future<void> save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _valid = const LessonEditorValidation.valid();
    });
    final outcome = await _flow.saveDraft(
      _session,
      _draft,
      _refs,
      () => _schedule.requestFor(session: _session, draft: _draft),
    );
    if (!mounted) return;
    try {
      switch (outcome) {
        case LessonSaveCreated():
          _finishSave('Занятие создано');
        case LessonSaveInvalid(:final validation):
          setState(() => _valid = validation);
        case LessonSaveViolations(:final violations):
          final analysis = LessonScheduleAnalysis.fromViolations(violations);
          setState(() => _conflicts = analysis);
          await _showViolations(violations);
        case LessonSaveDecision(:final request):
          final changed = await showLessonDecisionFlow(
            context,
            crm: ref.read(magicCrmServiceProvider),
            operation: request.operation,
            lesson: request.lesson,
            successor: request.successor,
            initialSettlementTypeKey: request.initialSettlementTypeKey,
            initialCompensationRuleKey: request.initialCompensationRuleKey,
            initialCompensationValueMinor:
                request.initialCompensationValueMinor,
          );
          if (changed == true && mounted) {
            _finishSave('Изменения занятия применены');
          }
        case LessonSaveFailure(:final error):
          _showError(error, 'Не удалось сохранить занятие.');
        case LessonSaveBusy():
          break;
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showViolations(List<LessonConstraintViolation> violations) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => LessonConstraintDialog(
          violations: violations,
          onOpen: (lessonId) {
            Navigator.pop(dialogContext);
            _focusConstraint(lessonId);
          },
          onFix: () => Navigator.pop(dialogContext),
        ),
      );
  void _focusConstraint(String lessonId) {
    final navigation = ref.read(scheduleNavigationProvider.notifier);
    navigation.focus(_draft.localStart, lessonId);
    Navigator.pop(context);
  }

  void cancel() => Navigator.pop(context);
  void _finishSave(String message) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context, true);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(Object error, String fallback) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(lessonEditorErrorMessage(error, fallback))),
    );
  }
}
