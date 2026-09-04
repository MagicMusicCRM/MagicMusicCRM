import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/models/student_lesson_timeline.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'student_lesson_timeline_controller.dart';

class RecurringSchedulePlanController extends ChangeNotifier {
  RecurringSchedulePlanController({
    required MagicCrmService service,
    this.studentId,
    this.groupId,
  }) : assert((studentId == null) != (groupId == null)),
       _service = service {
    final scopedStudentId = studentId;
    if (scopedStudentId != null) {
      _timeline = StudentLessonTimelineController(
        service: service,
        studentId: scopedStudentId,
      )..addListener(_timelineChanged);
    }
  }

  final MagicCrmService _service;
  final String? studentId;
  final String? groupId;

  StudentLessonTimelineController? _timeline;
  bool loading = false;
  String? error;
  List<SchedulePlan> plans = const [];
  bool _disposed = false;

  StudentLessonTimelinePage? get timelinePage => _timeline?.page;
  bool get timelineLoading => _timeline?.loading ?? false;
  bool get timelinePaging => _timeline?.paging ?? false;
  String? get timelineError => _timeline?.error;

  Future<void> load() async {
    loading = true;
    error = null;
    _notify();
    final timelineLoad = _timeline?.load();
    try {
      plans = await _service.listSchedulePlans(
        studentId: studentId,
        groupId: groupId,
      );
      if (timelineLoad != null) await timelineLoad;
    } catch (exception) {
      error = userErrorMessage(
        exception,
        fallback: 'Не удалось загрузить постоянное расписание.',
      );
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> previousTimeline() =>
      _timeline?.previous() ?? Future<void>.value();

  Future<void> nextTimeline() => _timeline?.next() ?? Future<void>.value();

  Future<void> retryTimeline() => _timeline?.retry() ?? Future<void>.value();

  void _timelineChanged() => _notify();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timeline?.removeListener(_timelineChanged);
    _timeline?.dispose();
    super.dispose();
  }
}
