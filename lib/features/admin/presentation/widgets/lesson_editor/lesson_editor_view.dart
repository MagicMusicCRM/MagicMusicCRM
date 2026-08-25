import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/models/lesson_schedule_analysis.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import '../lesson_decision/lesson_decision_models.dart';
import 'lesson_editor_decision_policy.dart';
import 'lesson_editor_feedback.dart';
import 'lesson_editor_models.dart';
import 'lesson_financial_section.dart';
import 'lesson_participant_section.dart';
import 'lesson_schedule_section.dart';

export 'lesson_editor_feedback.dart' show LessonEditorActions;

class LessonEditorViewModel {
  const LessonEditorViewModel({
    required this.session,
    required this.draft,
    required this.references,
    required this.analysis,
    required this.isLoading,
    required this.isSaving,
    required this.isAnalyzing,
    required this.validationMessage,
    this.scheduleAnalysisError,
  });

  final LessonEditorSession session;
  final LessonEditorDraft draft;
  final LessonEditorReferenceState references;
  final LessonScheduleAnalysis? analysis;
  final bool isLoading;
  final bool isSaving;
  final bool isAnalyzing;
  final String? validationMessage;
  final String? scheduleAnalysisError;
}

class LessonEditorView extends StatelessWidget {
  const LessonEditorView({
    required this.model,
    required this.actions,
    this.pageMode = false,
    this.title,
    this.scrollController,
    this.now,
    super.key,
  });

  final LessonEditorViewModel model;
  final LessonEditorActions actions;
  final bool pageMode;
  final String? title;
  final ScrollController? scrollController;
  final DateTime? now;

  String get _title {
    if (title != null) return title!;
    if (model.session.isEdit) return 'Перенести или изменить занятие';
    if (model.session.leadNoteSource != null) return 'Пробное занятие';
    return 'Новое занятие';
  }

  @override
  Widget build(BuildContext context) {
    if (model.isLoading) return _loadingSurface();

    const policy = LessonEditorDecisionPolicy();
    final selectedSettlement = _catalogItem(
      model.references.catalog?.settlementTypes,
      model.draft.settlementTypeKey,
    );
    final selectedRule = _catalogItem(
      model.references.catalog?.compensationRules,
      model.draft.compensationRuleKey,
    );
    final width = MediaQuery.sizeOf(context).width;
    final dialog = AlertDialog(
      insetPadding: pageMode ? EdgeInsets.zero : null,
      shape: pageMode
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
          : null,
      title: Row(
        children: [
          if (pageMode) ...[
            BackButton(onPressed: actions.cancel),
            const SizedBox(width: AppSpace.sm),
          ],
          Expanded(child: Text(_title)),
        ],
      ),
      contentPadding: pageMode
          ? const EdgeInsets.fromLTRB(16, 12, 16, 0)
          : null,
      content: SizedBox(
        width: pageMode
            ? double.maxFinite
            : width > 760
            ? 680
            : width - 80,
        height: pageMode ? double.maxFinite : null,
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LessonParticipantSection(
                model: LessonParticipantSectionModel(
                  session: model.session,
                  draft: model.draft,
                  references: model.references,
                  isDisabled: model.isSaving,
                ),
                onClientChanged: actions.selectClient,
                onBranchChanged: actions.selectBranch,
                onRoomChanged: actions.selectRoom,
                onTeacherChanged: actions.selectTeacher,
              ),
              const SizedBox(height: 16),
              LessonScheduleSection(
                model: LessonScheduleSectionModel.fromEditor(
                  draft: model.draft,
                  analysis: model.analysis,
                  isAnalyzing: model.isAnalyzing,
                  isEdit: model.session.isEdit,
                  now: now,
                  errorMessage: model.scheduleAnalysisError,
                  isSaving: model.isSaving,
                ),
                onAnalyze: actions.analyzeSchedule,
                onApplySuggestion: actions.applySuggestion,
                onOpenConstraint: actions.openConstraint,
                onDateChanged: actions.selectDate,
                onTimeChanged: actions.selectTime,
                onDurationChanged: actions.selectDuration,
              ),
              LessonFinancialSection(
                model: LessonFinancialSectionModel(
                  session: model.session,
                  draft: model.draft,
                  references: model.references,
                  isSaving: model.isSaving,
                  requiresCompensationValue: policy.requiresCompensationValue(
                    selectedRule,
                  ),
                  compensationNeedsReason: policy.compensationNeedsReason(
                    draft: model.draft,
                    rule: selectedRule,
                  ),
                  allowsNoFunding: policy.isNoCharge(selectedSettlement),
                ),
                actions: actions,
              ),
              LessonEditorFeedback(
                model: LessonEditorFeedbackModel(
                  session: model.session,
                  draft: model.draft,
                  validationMessage: model.validationMessage,
                  settlementLabel: selectedSettlement?.label ?? 'Не выбран',
                  clientSnapshotValue: policy.clientChargeSnapshotLabel(
                    draft: model.draft,
                    references: model.references,
                  ),
                  compensationLabel: selectedRule?.label ?? 'Не выбрано',
                  teacherSnapshotValue: policy.teacherCompensationSnapshotLabel(
                    draft: model.draft,
                    references: model.references,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        LessonEditorActionsRow(
          isEdit: model.session.isEdit,
          isSaving: model.isSaving,
          actions: actions,
        ),
      ],
    );
    return pageMode ? SafeArea(child: dialog) : dialog;
  }

  Widget _loadingSurface() {
    const loading = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.primaryGold),
          SizedBox(height: 16),
          Text('Загрузка данных...'),
        ],
      ),
    );
    return pageMode
        ? Scaffold(
            appBar: AppBar(title: Text(_title)),
            body: const SafeArea(top: false, child: loading),
          )
        : const AlertDialog(content: loading);
  }
}

LessonDecisionCatalogItem? _catalogItem(
  List<LessonDecisionCatalogItem>? items,
  String? key,
) {
  for (final item in items ?? const <LessonDecisionCatalogItem>[]) {
    if (item.key == key) return item;
  }
  return null;
}
