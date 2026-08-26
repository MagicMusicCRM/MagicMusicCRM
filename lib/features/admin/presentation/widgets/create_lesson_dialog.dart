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
import 'lesson_editor/lesson_editor_feedback.dart';
import 'lesson_editor/lesson_editor_initial_mapper.dart';
import 'lesson_editor/lesson_editor_models.dart';
import 'lesson_editor/lesson_editor_save_flow.dart';
import 'lesson_editor/lesson_editor_schedule_controller.dart';
import 'lesson_editor/lesson_editor_view.dart';

class CreateLessonDialog extends ConsumerStatefulWidget
    implements LessonEditorInitialSource {
  final DateTime? initialDate;
  final String? initialRoomId, initialBranchId;
  final int? initialDurationMinutes;
  final Map<String, dynamic>? lesson;
  final String? leadId;
  final String? leadName;
  final String? clientType;
  final String? clientId;
  final String? clientName;
  final bool initialIsTrial;
  final bool pageMode;
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

  ConsumerState<CreateLessonDialog> createState() => _LessonEditorDialogState();
}

class _LessonEditorDialogState extends ConsumerState<CreateLessonDialog>
    with LessonEditorDraftActions
    implements LessonEditorActions {
  static const _policy = LessonEditorDecisionPolicy();
  final _scroll = ScrollController(keepScrollOffset: false);
  late final LessonEditorSession _session;
  late LessonEditorDraft _draft;
  var _refs = const LessonEditorReferenceState.empty();
  late final LessonEditorDataController _data;
  late final LessonEditorScheduleController _schedule;
  late final LessonEditorSaveFlow _flow;
  bool _loading = true, _saving = false, _analyzing = false;
  String? _loadError, _scheduleError;
  LessonEditorValidation _valid = const LessonEditorValidation.valid();
  LessonScheduleAnalysis? _conflicts;
  LessonEditorDraft get actionDraft => _draft;
  LessonEditorReferenceState get actionReferences => _refs;
  LessonEditorDecisionPolicy get actionPolicy => _policy;
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
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final result = await _data.loadInitialSafely(_session);
    if (!mounted) return;
    if (result.patch case final patch?) {
      return _acceptPatch(patch, loaded: true);
    }
    setState(() {
      _loading = false;
      _loadError = lessonLoadErrorMessage(result.error);
    });
  }

  void _acceptPatch(LessonEditorLoadPatch patch, {bool loaded = false}) {
    final references = patch.references;
    final draft = _policy.applyReferenceDefaults(
      _session,
      patch.draft ?? _draft,
      references,
      widget.initialDurationMinutes == null,
    );
    setState(() {
      _draft = draft;
      _refs = references;
      if (loaded) _loading = false;
    });
  }

  void updateActionDraft(
    LessonEditorDraft value, {
    bool scheduleChanged = false,
  }) {
    setState(() {
      _draft = value;
      if (scheduleChanged) {
        _conflicts = null;
        _scheduleError = null;
      }
    });
  }

  Widget build(BuildContext context) => LessonEditorView(
    model: LessonEditorViewModel(
      session: _session,
      draft: _draft,
      references: _refs,
      analysis: _conflicts,
      isLoading: _loading,
      isSaving: _saving,
      isAnalyzing: _analyzing,
      validationMessage: _valid.message,
      loadErrorMessage: _loadError,
      scheduleAnalysisError: _scheduleError,
    ),
    actions: this,
    pageMode: widget.pageMode,
    title: lessonEditorTitle(_session, widget.leadId != null),
    scrollController: _scroll,
    onRetry: _refreshReferences,
  );
  Future<List<LessonClientRef>> searchClients(String query) =>
      _data.searchClients(query);
  void selectClient(LessonClientRef? value) => unawaited(
    _requestPatch(
      _data.selectClient(value, draft: _draft, references: _refs),
      'Не удалось выбрать клиента.',
    ),
  );
  void loadActionBranch(String value) {
    unawaited(
      _requestPatch(
        _data.loadBranch(value, draft: _draft, references: _refs),
        'Не удалось загрузить данные филиала.',
      ),
    );
  }

  LessonEditorDraft applyActionSuggestion(ScheduleSuggestion value) =>
      _schedule.applySuggestion(_draft, value);
  void focusActionConstraint(String lessonId) => _focusConstraint(lessonId);

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
    setState(() {
      _analyzing = true;
      _scheduleError = null;
    });
    final result = await _schedule.inspect(_session, _draft);
    if (!mounted) return;
    setState(() {
      _analyzing = false;
      _conflicts = result.analysis;
      _scheduleError = lessonScheduleErrorMessage(result.error);
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
          setState(
            () =>
                _conflicts = LessonScheduleAnalysis.fromViolations(violations),
          );
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
    ref
        .read(scheduleNavigationProvider.notifier)
        .focus(_draft.localStart, lessonId);
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
