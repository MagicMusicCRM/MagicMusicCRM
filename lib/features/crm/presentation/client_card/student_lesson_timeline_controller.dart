import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/student_lesson_timeline.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

class StudentLessonTimelineController extends ChangeNotifier {
  StudentLessonTimelineController({
    required MagicCrmService service,
    required String studentId,
    this.limit = 40,
    DateTime Function()? now,
  }) : _service = service,
       _studentId = studentId,
       _now = now ?? DateTime.now;

  final MagicCrmService _service;
  final int limit;
  final DateTime Function() _now;

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

  DateTime get _initialStart {
    final today = _now();
    return DateTime(today.year, today.month, today.day - 3);
  }

  DateTime _shift(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  Future<void> load() =>
      _request(_TimelineRequest(page.windowStart ?? _initialStart, false));

  Future<void> previous() {
    return _request(
      _TimelineRequest(_shift(page.windowStart ?? _initialStart, -30), true),
    );
  }

  Future<void> next() {
    return _request(
      _TimelineRequest(_shift(page.windowStart ?? _initialStart, 30), true),
    );
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
      final items = <String, StudentLessonTimelineItem>{};
      final cursors = <String>{};
      String? cursor;
      do {
        final result = await _service.listStudentLessonTimeline(
          studentId: requestedStudentId,
          cursor: cursor,
          limit: limit,
          from: request.start,
          to: _shift(request.start, 30),
        );
        if (!_isCurrent(generation, requestedStudentId)) return;
        for (final item in result.items) {
          items[item.id] = item;
        }
        if (!result.hasNext) break;
        cursor = result.nextCursor;
        if (cursor == null || !cursors.add(cursor)) {
          throw const FormatException('Timeline pagination did not advance');
        }
      } while (true);
      if (!_isCurrent(generation, requestedStudentId)) return;
      final ordered = items.values.toList()
        ..sort((a, b) {
          final time = a.scheduledAt.compareTo(b.scheduledAt);
          return time != 0 ? time : a.id.compareTo(b.id);
        });
      page = StudentLessonTimelinePage(
        items: List.unmodifiable(ordered),
        windowStart: request.start,
        previousCursor: null,
        nextCursor: null,
        hasPrevious: true,
        hasNext: true,
      );
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
  const _TimelineRequest(this.start, this.paging);
  final DateTime start;
  final bool paging;
}
