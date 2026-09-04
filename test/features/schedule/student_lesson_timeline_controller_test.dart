import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/student_lesson_timeline_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'service safely separates the encoded path from paging query values',
    () async {
      final adapter = _CaptureAdapter(_pageJson(const []));
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
        ..httpClientAdapter = adapter;
      final api = MagicApiClient(
        baseUrl: 'http://localhost',
        tokenStore: MemoryMagicTokenStore(),
        dio: dio,
      );

      await MagicCrmService(api).listStudentLessonTimeline(
        studentId: 'student/a ?',
        cursor: 'cursor+/=',
        direction: 'previous',
        limit: 40,
      );

      expect(
        adapter.uri?.path,
        '/crm/students/student%2Fa%20%3F/lesson-timeline',
      );
      expect(
        adapter.uri?.toString(),
        contains(
          '/crm/students/student%2Fa%20%3F/lesson-timeline?cursor=cursor%2B%2F%3D',
        ),
      );
      expect(adapter.uri?.queryParameters, {
        'cursor': 'cursor+/=',
        'direction': 'previous',
        'limit': '40',
      });
    },
  );

  test('paging replaces the visible page without mixing plan trays', () async {
    final api = _TimelineApi()
      ..enqueue(
        Future.value(
          _pageJson(
            const ['lesson-1', 'lesson-2'],
            nextCursor: 'cursor-next',
            hasNext: true,
          ),
        ),
      )
      ..enqueue(Future.value(_pageJson(const ['lesson-25', 'lesson-26'])));
    final controller = StudentLessonTimelineController(
      service: MagicCrmService(api),
      studentId: 'student-1',
    );
    addTearDown(controller.dispose);

    await controller.load();
    await controller.next();

    expect(controller.page.items.map((item) => item.id), [
      'lesson-25',
      'lesson-26',
    ]);
    expect(
      api.requests.map((request) => request.path),
      everyElement('/crm/students/student-1/lesson-timeline'),
    );
    expect(api.requests.last.query, {
      'cursor': 'cursor-next',
      'direction': 'next',
      'limit': 24,
    });
  });

  test(
    'paging failure preserves the page and retry repeats that page request',
    () async {
      final api = _TimelineApi()
        ..enqueue(
          Future.value(
            _pageJson(
              const ['lesson-1'],
              previousCursor: 'cursor-before',
              hasPrevious: true,
            ),
          ),
        )
        ..enqueue(Future.error(StateError('offline')))
        ..enqueue(Future.value(_pageJson(const ['lesson-before'])));
      final controller = StudentLessonTimelineController(
        service: MagicCrmService(api),
        studentId: 'student-1',
      );
      addTearDown(controller.dispose);

      await controller.load();
      await controller.previous();

      expect(controller.page.items.single.id, 'lesson-1');
      expect(controller.error, isNotNull);
      expect(controller.paging, isFalse);

      await controller.retry();

      expect(controller.page.items.single.id, 'lesson-before');
      expect(controller.error, isNull);
      expect(api.requests[1].query, api.requests[2].query);
    },
  );

  test(
    'late success from the previous student cannot replace the current page',
    () async {
      final stale = Completer<Map<String, dynamic>>();
      final api = _TimelineApi()
        ..enqueue(stale.future)
        ..enqueue(Future.value(_pageJson(const ['student-b-lesson'])));
      final controller = StudentLessonTimelineController(
        service: MagicCrmService(api),
        studentId: 'student-a',
      );
      addTearDown(controller.dispose);

      final staleLoad = controller.load();
      controller.setStudentId('student-b');
      await controller.load();
      stale.complete(_pageJson(const ['student-a-lesson']));
      await staleLoad;

      expect(controller.page.items.single.id, 'student-b-lesson');
      expect(controller.loading, isFalse);
      expect(controller.error, isNull);
    },
  );

  test(
    'late failure from the previous student cannot set error or loading',
    () async {
      final stale = Completer<Map<String, dynamic>>();
      final api = _TimelineApi()
        ..enqueue(stale.future)
        ..enqueue(Future.value(_pageJson(const ['student-b-lesson'])));
      final controller = StudentLessonTimelineController(
        service: MagicCrmService(api),
        studentId: 'student-a',
      );
      addTearDown(controller.dispose);

      final staleLoad = controller.load();
      controller.setStudentId('student-b');
      await controller.load();
      stale.completeError(StateError('stale offline'));
      await staleLoad;

      expect(controller.page.items.single.id, 'student-b-lesson');
      expect(controller.loading, isFalse);
      expect(controller.paging, isFalse);
      expect(controller.error, isNull);
    },
  );
}

Map<String, dynamic> _pageJson(
  List<String> ids, {
  String? previousCursor,
  String? nextCursor,
  bool hasPrevious = false,
  bool hasNext = false,
}) => {
  'items': [for (final id in ids) _itemJson(id)],
  'previousCursor': previousCursor,
  'nextCursor': nextCursor,
  'hasPrevious': hasPrevious,
  'hasNext': hasNext,
};

Map<String, dynamic> _itemJson(String id) => {
  'id': id,
  'version': 1,
  'scheduledAt': '2026-09-04T12:30:00.000Z',
  'durationMinutes': 60,
  'lifecycleState': 'scheduled',
  'student': {'id': 'student-1', 'name': 'Анна Петрова'},
  'group': null,
  'teacher': null,
  'room': null,
  'branch': null,
  'origin': {'kind': 'manual', 'planId': null, 'seriesId': null},
  'settlement': {'coveredBySubscription': false, 'settlementTypeKey': null},
  'reschedule': {
    'predecessorId': null,
    'successorId': null,
    'actionableLessonId': id,
  },
};

class _TimelineRequest {
  const _TimelineRequest(this.path, this.query);

  final String path;
  final Map<String, dynamic> query;
}

class _TimelineApi extends MagicApiClient {
  _TimelineApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<Future<Map<String, dynamic>>> _responses = [];
  final List<_TimelineRequest> requests = [];

  void enqueue(Future<Map<String, dynamic>> response) =>
      _responses.add(response);

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    requests.add(
      _TimelineRequest(
        path,
        Map<String, dynamic>.from(queryParameters ?? const {}),
      ),
    );
    final response = await _responses.removeAt(0);
    return response as T;
  }
}

class _CaptureAdapter implements HttpClientAdapter {
  _CaptureAdapter(this.body);

  final Map<String, dynamic> body;
  Uri? uri;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    uri = options.uri;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
