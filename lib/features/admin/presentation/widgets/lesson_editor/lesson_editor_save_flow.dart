import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import '../lesson_decision/lesson_decision_models.dart';
import 'lesson_editor_decision_policy.dart';
import 'lesson_editor_models.dart';

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
  });

  final LessonEditorScheduleRequest scheduleRequest;
  final Map<String, dynamic> payload;
  final LessonDecisionRequest? decisionRequest;
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
  const LessonSaveDecision(this.request);

  final LessonDecisionRequest request;
}

final class LessonSaveBusy extends LessonSaveOutcome {
  const LessonSaveBusy();
}

final class LessonSaveInvalid extends LessonSaveOutcome {
  const LessonSaveInvalid(this.validation);

  final LessonEditorValidation validation;
}

final class LessonSaveFailure extends LessonSaveOutcome {
  const LessonSaveFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

typedef LessonSchedulePreview =
    Future<LessonScheduleAnalysis> Function(
      LessonEditorScheduleRequest request,
    );
typedef LessonCreate =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> payload);

class LessonEditorSaveFlow {
  LessonEditorSaveFlow.forTesting({
    required LessonSchedulePreview preview,
    required LessonCreate create,
  }) : _preview = preview,
       _create = create;

  LessonEditorSaveFlow.fromCrm(MagicCrmService crm)
    : this.forTesting(
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
      );

  final LessonSchedulePreview _preview;
  final LessonCreate _create;
  bool _saving = false;

  Future<LessonSaveOutcome> saveDraft(
    LessonEditorSession session,
    LessonEditorDraft draft,
    LessonEditorReferenceState references,
    LessonEditorScheduleRequest Function() scheduleRequest, {
    required bool canManageTeacherCompensation,
    LessonEditorDecisionPolicy policy = const LessonEditorDecisionPolicy(),
  }) {
    final validation = policy.validate(
      session: session,
      draft: draft,
      references: references,
    );
    if (!validation.isValid) return Future.value(LessonSaveInvalid(validation));
    return save(
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
        decisionRequest: session.isEdit
            ? policy.editRequest(session: session, draft: draft)
            : null,
      ),
    );
  }

  Future<LessonSaveOutcome> save(LessonEditorSaveCommand command) async {
    if (_saving) return const LessonSaveBusy();
    _saving = true;
    try {
      final decision = command.decisionRequest;
      if (decision != null) return LessonSaveDecision(decision);
      final previewOutcome = await _previewOutcome(command.scheduleRequest);
      if (previewOutcome != null) return previewOutcome;
      return await _createOutcome(command.payload);
    } finally {
      _saving = false;
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
