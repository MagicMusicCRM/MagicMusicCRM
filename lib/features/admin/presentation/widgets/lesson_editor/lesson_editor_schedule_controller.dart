import 'dart:async';

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
    LessonScheduleAnalysisRunner? analyzeTeacherAvailability,
  }) : _policy = policy,
       _analyze = analyze,
       _analyzeTeacherAvailability = analyzeTeacherAvailability ?? analyze;

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
         analyzeTeacherAvailability: (request) => crm.analyzeLessonSchedule(
           clientType: request.clientType,
           clientId: request.clientId,
           teacherId: request.teacherId,
           branchId: request.branchId,
           roomId: request.roomId,
           scheduledAt: request.scheduledAt,
           durationMinutes: request.durationMinutes,
           excludeLessonId: request.excludeLessonId,
           includeSuggestions: false,
         ),
       );

  final LessonEditorDecisionPolicy _policy;
  final LessonScheduleAnalysisRunner _analyze;
  final LessonScheduleAnalysisRunner _analyzeTeacherAvailability;
  Set<String> availableTeacherIds = {};
  bool teacherOptionsLoading = false;
  String? teacherOptionsError;
  String? _teacherOptionsKey;
  int _teacherOptionsGeneration = 0;
  Timer? _previewTimer;

  void cancelPreview() => _previewTimer?.cancel();

  void dispose() {
    cancelPreview();
    invalidateTeacherOptions();
  }

  void queuePreview(
    LessonEditorSession session,
    LessonEditorDraft draft,
    void Function() run,
  ) {
    cancelPreview();
    try {
      requestFor(session: session, draft: draft);
    } on StateError {
      return;
    }
    _previewTimer = Timer(const Duration(milliseconds: 300), run);
  }

  void invalidateTeacherOptions() {
    ++_teacherOptionsGeneration;
    _teacherOptionsKey = null;
    availableTeacherIds = {};
    teacherOptionsLoading = false;
    teacherOptionsError = null;
  }

  Future<LessonEditorDraft?> refreshTeacherOptions({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
    required void Function() onChanged,
    bool force = false,
  }) async {
    final client = draft.client;
    final branchId = draft.branchId;
    final roomId =
        draft.roomId ??
        references.rooms
            .where(
              (room) => room.branchId == branchId && room.status != 'archived',
            )
            .firstOrNull
            ?.id;
    if (client == null || branchId == null || roomId == null) {
      invalidateTeacherOptions();
      onChanged();
      return null;
    }
    final candidates = references.teachers
        .where(
          (teacher) =>
              teacher.isWorkingTeacher &&
              teacher.assignedBranchIds.contains(branchId),
        )
        .toList();
    final key = [
      client.key,
      branchId,
      roomId,
      _policy.schedulePayload(draft)['scheduledAt'],
      draft.durationMinutes,
      session.snapshot?.lessonId,
      candidates.map((teacher) => teacher.id).join(','),
    ].join('|');
    if (!force &&
        _teacherOptionsKey == key &&
        (teacherOptionsLoading || teacherOptionsError == null)) {
      return null;
    }
    final generation = ++_teacherOptionsGeneration;
    _teacherOptionsKey = key;
    availableTeacherIds = {};
    teacherOptionsLoading = true;
    teacherOptionsError = null;
    onChanged();
    final available = <String>{};
    try {
      // ponytail: four parallel previews bound DB load; batch if branches regularly exceed 100 teachers.
      for (var index = 0; index < candidates.length; index += 4) {
        final chunk = candidates.skip(index).take(4).toList();
        final results = await Future.wait([
          for (final teacher in chunk)
            _analyzeTeacherAvailability(
              requestFor(
                session: session,
                draft: draft.copyWith(teacherId: teacher.id, roomId: roomId),
              ),
            ),
        ]);
        if (generation != _teacherOptionsGeneration) return null;
        for (var i = 0; i < chunk.length; i++) {
          final blocked = results[i].violations.any(
            (violation) => const {
              'INVALID_INTERVAL',
              'OUTSIDE_BRANCH_HOURS',
              'TEACHER_UNAVAILABLE',
              'TEACHER_BRANCH_MISMATCH',
              'TEACHER_OVERLAP',
            }.contains(violation.code),
          );
          if (!blocked) available.add(chunk[i].id);
        }
      }
      if (generation != _teacherOptionsGeneration) return null;
      availableTeacherIds = available;
      teacherOptionsLoading = false;
      onChanged();
      return null;
    } catch (_) {
      if (generation != _teacherOptionsGeneration) return null;
      teacherOptionsError = 'Не удалось проверить доступность преподавателей.';
      teacherOptionsLoading = false;
      onChanged();
      return null;
    }
  }

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
    cancelPreview();
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
