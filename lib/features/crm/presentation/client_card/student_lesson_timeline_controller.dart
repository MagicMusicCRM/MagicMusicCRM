import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/student_lesson_timeline.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

class StudentLessonTimelineController extends ChangeNotifier {
  StudentLessonTimelineController({
    required MagicCrmService service,
    required String studentId,
    this.limit = 24,
  }) : _service = service,
       _studentId = studentId;

  final MagicCrmService _service;
  final int limit;

  String _studentId;
  StudentLessonTimelinePage page = const StudentLessonTimelinePage.empty();
  bool loading = false;
  bool paging = false;
  String? error;

  int _requestGeneration = 0;
  _TimelineRequest? _retryRequest;
  bool _disposed = false;

  String get studentId => _studentId;

  void setStudentId(String studentId) {
    if (studentId == _studentId) return;
    _studentId = studentId;
    _requestGeneration++;
    page = const StudentLessonTimelinePage.empty();
    loading = false;
    paging = false;
    error = null;
    _retryRequest = null;
    _notify();
  }

  Future<void> load() => _request(const _TimelineRequest.initial());

  Future<void> previous() {
    final cursor = page.previousCursor;
    if (!page.hasPrevious || cursor == null) return Future.value();
    return _request(_TimelineRequest.page(cursor, 'previous'));
  }

  Future<void> next() {
    final cursor = page.nextCursor;
    if (!page.hasNext || cursor == null) return Future.value();
    return _request(_TimelineRequest.page(cursor, 'next'));
  }

  Future<void> retry() {
    final request = _retryRequest;
    if (request == null) return Future.value();
    return _request(request);
  }

  Future<void> _request(_TimelineRequest request) async {
    if (loading || paging) return;
    final generation = ++_requestGeneration;
    final requestedStudentId = _studentId;
    if (request.paging) {
      paging = true;
    } else {
      loading = true;
    }
    error = null;
    _notify();
    try {
      final result = await _service.listStudentLessonTimeline(
        studentId: requestedStudentId,
        cursor: request.cursor,
        direction: request.direction,
        limit: limit,
      );
      if (!_isCurrent(generation, requestedStudentId)) return;
      page = result;
      _retryRequest = null;
    } catch (exception) {
      if (!_isCurrent(generation, requestedStudentId)) return;
      error = userErrorMessage(
        exception,
        fallback: 'Не удалось загрузить историю занятий.',
      );
      _retryRequest = request;
    } finally {
      if (_isCurrent(generation, requestedStudentId)) {
        loading = false;
        paging = false;
        _notify();
      }
    }
  }

  bool _isCurrent(int generation, String requestedStudentId) =>
      !_disposed &&
      generation == _requestGeneration &&
      requestedStudentId == _studentId;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _requestGeneration++;
    super.dispose();
  }
}

class _TimelineRequest {
  const _TimelineRequest({
    required this.cursor,
    required this.direction,
    required this.paging,
  });

  const _TimelineRequest.initial()
    : cursor = null,
      direction = 'next',
      paging = false;

  const _TimelineRequest.page(this.cursor, this.direction) : paging = true;

  final String? cursor;
  final String direction;
  final bool paging;
}
