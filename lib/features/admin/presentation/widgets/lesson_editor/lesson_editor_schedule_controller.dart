import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import 'lesson_editor_decision_policy.dart';
import 'lesson_editor_models.dart';
import 'lesson_editor_save_flow.dart';

typedef LessonScheduleAnalysisRunner =
    Future<LessonScheduleAnalysis> Function(
      LessonEditorScheduleRequest request,
    );

class LessonEditorScheduleInspection {
  const LessonEditorScheduleInspection({this.analysis, this.error});

  final LessonScheduleAnalysis? analysis;
  final Object? error;
}

class LessonEditorScheduleController {
  LessonEditorScheduleController({
    required LessonEditorDecisionPolicy policy,
    required LessonScheduleAnalysisRunner analyze,
  }) : _policy = policy,
       _analyze = analyze;

  LessonEditorScheduleController.fromCrm(
    MagicCrmService crm, {
    LessonEditorDecisionPolicy policy = const LessonEditorDecisionPolicy(),
  }) : this(
         policy: policy,
         analyze: (request) => crm.analyzeLessonSchedule(
           clientType: request.clientType,
           clientId: request.clientId,
           teacherId: request.teacherId,
           branchId: request.branchId,
           roomId: request.roomId,
           scheduledAt: request.scheduledAt,
           durationMinutes: request.durationMinutes,
           excludeLessonId: request.excludeLessonId,
         ),
       );

  final LessonEditorDecisionPolicy _policy;
  final LessonScheduleAnalysisRunner _analyze;

  LessonEditorScheduleRequest requestFor({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
  }) {
    final client = draft.client;
    final teacherId = draft.teacherId;
    final branchId = draft.branchId;
    final roomId = draft.roomId;
    if (client == null ||
        teacherId == null ||
        branchId == null ||
        roomId == null) {
      throw StateError('Lesson schedule request is incomplete');
    }
    final payload = _policy.schedulePayload(draft);
    return LessonEditorScheduleRequest(
      clientType: client.type,
      clientId: client.id,
      teacherId: teacherId,
      branchId: branchId,
      roomId: roomId,
      scheduledAt: payload['scheduledAt']! as String,
      durationMinutes: draft.durationMinutes,
      excludeLessonId: session.snapshot?.lessonId,
    );
  }

  Future<LessonScheduleAnalysis> analyze({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
  }) => _analyze(requestFor(session: session, draft: draft));

  Future<LessonEditorScheduleInspection> inspect(
    LessonEditorSession session,
    LessonEditorDraft draft,
  ) async {
    try {
      return LessonEditorScheduleInspection(
        analysis: await analyze(session: session, draft: draft),
      );
    } catch (error) {
      return LessonEditorScheduleInspection(error: error);
    }
  }

  LessonEditorDraft applySuggestion(
    LessonEditorDraft draft,
    ScheduleSuggestion suggestion,
  ) => draft.copyWith(
    teacherId: suggestion.teacherId ?? draft.teacherId,
    roomId: suggestion.roomId ?? draft.roomId,
    localStart: suggestion.startAt ?? draft.localStart,
  );
}
