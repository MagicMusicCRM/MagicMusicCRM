import 'dart:convert';

import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import '../lesson_decision/lesson_decision_models.dart';
import '../lesson_decision/lesson_decision_controller.dart';
import 'lesson_editor_decision_policy.dart';
import 'lesson_editor_models.dart';
import 'lesson_transition_error.dart';

export 'lesson_transition_error.dart';

class LessonEditorScheduleRequest {
  const LessonEditorScheduleRequest({
    required this.clientType,
    required this.clientId,
    required this.teacherId,
    required this.branchId,
    required this.roomId,
    required this.scheduledAt,
    required this.durationMinutes,
    this.excludeLessonId,
  });

  final String clientType;
  final String clientId;
  final String teacherId;
  final String branchId;
  final String roomId;
  final String scheduledAt;
  final int durationMinutes;
  final String? excludeLessonId;
}

class LessonEditorSaveCommand {
  const LessonEditorSaveCommand({
    required this.scheduleRequest,
    required this.payload,
    this.decisionRequest,
    this.noteUpdate,
  });

  final LessonEditorScheduleRequest scheduleRequest;
  final Map<String, dynamic> payload;
  final LessonDecisionRequest? decisionRequest;
  final LessonNoteUpdate? noteUpdate;
}

class LessonNoteUpdate {
  const LessonNoteUpdate({
    required this.lessonId,
    required this.expectedVersion,
    required this.notes,
    required this.identity,
  });

  final String lessonId;
  final int expectedVersion;
  final String notes;
  final MagicMutationIdentity identity;
}

class _LessonNotesMutationAttempt {
  const _LessonNotesMutationAttempt({
    required this.fingerprint,
    required this.identity,
  });

  final String fingerprint;
  final MagicMutationIdentity identity;
}

sealed class LessonSaveOutcome {
  const LessonSaveOutcome();
}

final class LessonSaveCreated extends LessonSaveOutcome {
  const LessonSaveCreated(this.lesson);

  final Map<String, dynamic> lesson;
}

final class LessonSaveViolations extends LessonSaveOutcome {
  const LessonSaveViolations(this.violations);

  final List<LessonConstraintViolation> violations;
}

final class LessonSaveDecision extends LessonSaveOutcome {
  const LessonSaveDecision(this.request, {this.noteUpdate});

  final LessonDecisionRequest request;
  final LessonNoteUpdate? noteUpdate;
}

final class LessonSaveNotes extends LessonSaveOutcome {
  const LessonSaveNotes(this.lesson);

  final Map<String, dynamic> lesson;
}

final class LessonSavePreview extends LessonSaveOutcome {
  const LessonSavePreview(this.preview);

  final LessonDecisionPreview preview;
}

final class LessonSaveConfirmed extends LessonSaveOutcome {
  const LessonSaveConfirmed(this.lesson);

  final Map<String, dynamic> lesson;
}

final class LessonSaveBusy extends LessonSaveOutcome {
  const LessonSaveBusy();
}

final class LessonSaveInvalid extends LessonSaveOutcome {
  const LessonSaveInvalid(this.validation);

  final LessonEditorValidation validation;
}

final class LessonSaveFailure extends LessonSaveOutcome {
  const LessonSaveFailure(this.error, this.stackTrace, {this.reloadedSession});

  final Object error;
  final StackTrace stackTrace;
  final LessonEditorSession? reloadedSession;
}

typedef LessonSchedulePreview =
    Future<LessonScheduleAnalysis> Function(
      LessonEditorScheduleRequest request,
    );
typedef LessonCreate =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> payload);
typedef LessonNotesUpdate =
    Future<Map<String, dynamic>> Function(LessonNoteUpdate update);

class LessonEditorSaveFlow {
  LessonEditorSaveFlow.forTesting({
    required LessonSchedulePreview preview,
    required LessonCreate create,
    LessonNotesUpdate? updateNotes,
    MagicCrmService? crm,
  }) : _preview = preview,
       _create = create,
       _updateNotes = updateNotes,
       _crm = crm;

  LessonEditorSaveFlow.fromCrm(MagicCrmService crm)
    : this.forTesting(
        crm: crm,
        preview: (request) => crm.analyzeLessonSchedule(
          clientType: request.clientType,
          clientId: request.clientId,
          teacherId: request.teacherId,
          branchId: request.branchId,
          roomId: request.roomId,
          scheduledAt: request.scheduledAt,
          durationMinutes: request.durationMinutes,
          excludeLessonId: request.excludeLessonId,
        ),
        create: crm.createLessonRaw,
        updateNotes: (update) => crm.updateLessonNotes(
          lessonId: update.lessonId,
          expectedVersion: update.expectedVersion,
          notes: update.notes,
          identity: update.identity,
        ),
      );

  final LessonSchedulePreview _preview;
  final LessonCreate _create;
  final LessonNotesUpdate? _updateNotes;
  final MagicCrmService? _crm;
  _LessonNotesMutationAttempt? _notesAttempt;
  bool _saving = false;
  bool _advancing = false;
  LessonDecisionController? _decisionController;
  LessonDecisionPreview? _financialPreview;

  LessonDecisionPreview? get financialPreview => _financialPreview;

  void invalidateDecision() {
    _decisionController = null;
    _financialPreview = null;
  }

  /// One editor submission: create, preview an edit, or confirm its signed result.
  Future<LessonSaveOutcome> advance(
    LessonEditorSession session,
    LessonEditorDraft draft,
    LessonEditorReferenceState references,
    LessonEditorScheduleRequest Function() scheduleRequest, {
    required bool canManageTeacherCompensation,
    required Future<LessonEditorSession> Function(String? actionableLessonId)
    reloadSession,
  }) async {
    if (_advancing) return const LessonSaveBusy();
    _advancing = true;
    try {
      if (_decisionController == null) {
        final outcome = await saveDraft(
          session,
          draft,
          references,
          scheduleRequest,
          canManageTeacherCompensation: canManageTeacherCompensation,
        );
        if (outcome is! LessonSaveDecision) return outcome;
        if (draft.plannedSettlementReason.trim().length < 3) {
          return const LessonSaveInvalid(
            LessonEditorValidation.invalid(
              'Укажите причину изменения (от 3 символов)',
            ),
          );
        }
        _decisionController = _controllerFor(
          outcome,
          canManageTeacherCompensation,
        );
      } else if (_financialPreview?.canConfirm == true) {
        final lesson = await _decisionController!.commit(_financialPreview!);
        invalidateDecision();
        return LessonSaveConfirmed(lesson);
      }
      final preview = await _decisionController!.preview(
        reason: draft.plannedSettlementReason,
        settlementTypeKey: draft.settlementTypeKey!,
        compensationRuleKey: draft.compensationRuleKey ?? '',
        compensationValueMinor: draft.compensationValueMinor,
        clientDecisions: draft.clientDecisions,
      );
      _financialPreview = preview;
      return LessonSavePreview(preview);
    } catch (error, stackTrace) {
      final recovered = await _decisionController?.recoverStaleCommit(error);
      if (recovered == null) {
        return LessonSaveFailure(mapLessonTransitionFailure(error), stackTrace);
      }
      invalidateDecision();
      try {
        return LessonSaveFailure(
          recovered,
          stackTrace,
          reloadedSession: await reloadSession(
            lessonTransitionActionableLessonId(error),
          ),
        );
      } catch (reloadError, reloadStackTrace) {
        return LessonSaveFailure(reloadError, reloadStackTrace);
      }
    } finally {
      _advancing = false;
    }
  }

  LessonDecisionController _controllerFor(
    LessonSaveDecision decision,
    bool canManageTeacherCompensation,
  ) {
    final request = decision.request;
    return LessonDecisionController(
      crm: _crm!,
      operation: request.operation,
      lesson: request.lesson,
      successor: request.successor,
      resources: request.resources,
      canManageTeacherCompensation: canManageTeacherCompensation,
      afterCommit: decision.noteUpdate == null
          ? null
          : (result) => saveConfirmedNotes(decision.noteUpdate!, result),
    );
  }

  Future<LessonSaveOutcome> saveDraft(
    LessonEditorSession session,
    LessonEditorDraft draft,
    LessonEditorReferenceState references,
    LessonEditorScheduleRequest Function() scheduleRequest, {
    required bool canManageTeacherCompensation,
    LessonEditorDecisionPolicy policy = const LessonEditorDecisionPolicy(),
  }) async {
    try {
      final validation = policy.validate(
        session: session,
        draft: draft,
        references: references,
      );
      if (!validation.isValid) return LessonSaveInvalid(validation);
      final decision =
          session.isEdit &&
              (policy.hasScheduleChanges(session: session, draft: draft) ||
                  policy.hasFinancialChanges(session: session, draft: draft) ||
                  session.snapshot?.rawLesson['lifecycle_state'] ==
                      'settlement_pending')
          ? policy.editRequest(session: session, draft: draft)
          : null;
      return await save(
        LessonEditorSaveCommand(
          scheduleRequest: scheduleRequest(),
          payload: session.isEdit
              ? policy.schedulePayload(draft)
              : policy.createPayload(
                  session: session,
                  draft: draft,
                  references: references,
                  canManageTeacherCompensation: canManageTeacherCompensation,
                ),
          decisionRequest: decision,
          noteUpdate:
              session.isEdit &&
                  policy.hasNotesChanges(session: session, draft: draft)
              ? _noteUpdateFor(session, draft, decision)
              : null,
        ),
      );
    } catch (error, stackTrace) {
      return LessonSaveFailure(error, stackTrace);
    }
  }

  Future<LessonSaveOutcome> save(LessonEditorSaveCommand command) async {
    if (_saving) return const LessonSaveBusy();
    _saving = true;
    try {
      final decision = command.decisionRequest;
      final noteUpdate = command.noteUpdate;
      if (decision != null) {
        return LessonSaveDecision(decision, noteUpdate: noteUpdate);
      }
      if (noteUpdate != null) {
        final updateNotes = _updateNotes;
        if (updateNotes == null) {
          throw StateError('Lesson note update is not configured.');
        }
        final lesson = await updateNotes(noteUpdate);
        _completeNotesAttempt(noteUpdate);
        return LessonSaveNotes(lesson);
      }
      final previewOutcome = await _previewOutcome(command.scheduleRequest);
      if (previewOutcome != null) return previewOutcome;
      return await _createOutcome(command.payload);
    } catch (error, stackTrace) {
      return LessonSaveFailure(error, stackTrace);
    } finally {
      _saving = false;
    }
  }

  Future<Map<String, dynamic>> saveConfirmedNotes(
    LessonNoteUpdate update,
    Map<String, dynamic> decision,
  ) async {
    final updateNotes = _updateNotes;
    if (updateNotes == null) {
      throw StateError('Lesson note update is not configured.');
    }
    final source = decision['source'];
    final version =
        ((source is Map ? source['version'] : null) ?? decision['version'])
            as num?;
    if (version == null || version.toInt() < 1) {
      throw StateError('Версия занятия после решения не получена.');
    }
    final lesson = await updateNotes(
      LessonNoteUpdate(
        lessonId: update.lessonId,
        expectedVersion: version.toInt(),
        notes: update.notes,
        identity: update.identity,
      ),
    );
    _completeNotesAttempt(update);
    return lesson;
  }

  LessonNoteUpdate _noteUpdateFor(
    LessonEditorSession session,
    LessonEditorDraft draft,
    LessonDecisionRequest? decision,
  ) {
    final snapshot = session.snapshot!;
    final fingerprint = jsonEncode({
      'lessonId': snapshot.lessonId,
      'expectedVersion': snapshot.expectedVersion,
      'notes': draft.notes.trim(),
      'decision': decision == null
          ? null
          : {
              'operation': decision.operation.apiKey,
              'lesson': decision.lesson,
              'successor': decision.successor,
              'successorFinancialDecision': decision.successorFinancialDecision,
            },
    });
    final previous = _notesAttempt;
    final attempt = previous?.fingerprint == fingerprint
        ? previous!
        : _LessonNotesMutationAttempt(
            fingerprint: fingerprint,
            identity: MagicMutationIdentity.create(
              'lesson-notes-${snapshot.lessonId}',
            ),
          );
    _notesAttempt = attempt;
    return LessonNoteUpdate(
      lessonId: snapshot.lessonId,
      expectedVersion: snapshot.expectedVersion!,
      notes: draft.notes,
      identity: attempt.identity,
    );
  }

  void _completeNotesAttempt(LessonNoteUpdate update) {
    if (identical(_notesAttempt?.identity, update.identity)) {
      _notesAttempt = null;
    }
  }

  Future<LessonSaveViolations?> _previewOutcome(
    LessonEditorScheduleRequest request,
  ) async {
    try {
      final analysis = await _preview(request);
      if (analysis.valid) return null;
      return LessonSaveViolations(analysis.violations);
    } catch (_) {
      // The authoritative create transaction repeats every hard constraint.
      return null;
    }
  }

  Future<LessonSaveOutcome> _createOutcome(Map<String, dynamic> payload) async {
    try {
      return LessonSaveCreated(await _create(payload));
    } on MagicApiException catch (error, stackTrace) {
      final violations = _constraintViolations(error);
      if (violations != null) return LessonSaveViolations(violations);
      return LessonSaveFailure(error, stackTrace);
    } catch (error, stackTrace) {
      return LessonSaveFailure(error, stackTrace);
    }
  }

  List<LessonConstraintViolation>? _constraintViolations(
    MagicApiException error,
  ) {
    if (error.statusCode != 422) return null;
    final violations = lessonConstraintViolationsFromDetails(error.details);
    return violations == null || violations.isEmpty ? null : violations;
  }
}
