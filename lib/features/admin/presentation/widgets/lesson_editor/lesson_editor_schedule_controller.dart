import 'package:magic_music_crm/core/models/lesson_schedule_analysis.dart';

import 'lesson_editor_decision_policy.dart';
import 'lesson_editor_models.dart';
import 'lesson_editor_save_flow.dart';

class LessonEditorScheduleController {
  LessonEditorScheduleController({
    required LessonEditorDecisionPolicy policy,
    required Future<LessonScheduleAnalysis> Function(
      LessonEditorScheduleRequest request,
    )
    analyze,
  }) : _policy = policy,
       _analyze = analyze;

  final LessonEditorDecisionPolicy _policy;
  final LessonSchedulePreview _analyze;

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

  LessonEditorDraft applySuggestion(
    LessonEditorDraft draft,
    ScheduleSuggestion suggestion,
  ) => draft.copyWith(
    teacherId: suggestion.teacherId ?? draft.teacherId,
    roomId: suggestion.roomId ?? draft.roomId,
    localStart: suggestion.startAt ?? draft.localStart,
  );
}
