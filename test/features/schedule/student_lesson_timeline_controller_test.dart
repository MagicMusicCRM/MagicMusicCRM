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
    'fills thirty occupied dates across months and never splits the final day',
    () async {
      Map<String, dynamic> lesson(int day, int index) => {
        ..._itemJson('day-$day-$index'),
        'scheduledAt': DateTime(
          2026,
          9,
          7 + day * 7,
          10,
          index,
        ).toIso8601String(),
      };
      final api = _TimelineApi()
        ..enqueue(
          Future.value({
            ..._pageJson([], hasNext: true, nextCursor: 'next-date-page'),
            'items': [
              for (var i = 0; i < 29; i++) lesson(i, 0),
              for (var i = 0; i < 11; i++) lesson(29, i),
            ],
          }),
        )
        ..enqueue(
          Future.value({
            ..._pageJson([], hasNext: true, nextCursor: 'unused'),
            'items': [lesson(29, 11), lesson(29, 12), lesson(30, 0)],
          }),
        )
        ..enqueue(
          Future.value({
            ..._pageJson([]),
            'items': [lesson(30, 0)],
          }),
        );
      final controller = StudentLessonTimelineController(
        service: MagicCrmService(api),
        studentId: 'student-1',
        now: () => DateTime(2026, 9, 10),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.page.items.length, 42);
      expect(controller.page.items.last.id, 'day-29-12');
      expect(
        controller.page.items.any((item) => item.id == 'day-30-0'),
        isFalse,
      );
      expect(
        api.requests.first.query['anchor'],
        DateTime(2026, 9, 7).toUtc().toIso8601String(),
      );
      expect(api.requests[1].query.containsKey('anchor'), isFalse);
      expect(api.requests[1].query['cursor'], 'next-date-page');
      await controller.next();
      expect(
        api.requests.last.query['anchor'],
        DateTime(2026, 9, 7 + 29 * 7 + 1).toUtc().toIso8601String(),
      );
      expect(controller.page.items.single.id, 'day-30-0');
      expect(controller.page.hasNext, isFalse);
    },
  );

  test(
    'previous page selects the nearest thirty dates in chronological order',
    () async {
      final api = _TimelineApi()
        ..enqueue(Future.value(_pageJson(['current'])))
        ..enqueue(
          Future.value({
            ..._pageJson([], hasPrevious: true, previousCursor: 'older'),
            'items': [
              for (var i = 0; i < 31; i++)
                {
                  ..._itemJson('past-$i'),
                  'scheduledAt': DateTime(2026, 8, 1 - i, 15).toIso8601String(),
                },
            ],
          }),
        );
      final controller = StudentLessonTimelineController(
        service: MagicCrmService(api),
        studentId: 'student-1',
      );
      addTearDown(controller.dispose);
      await controller.load();
      await controller.previous();
      expect(controller.page.items.length, 30);
      expect(controller.page.items.first.id, 'past-29');
      expect(controller.page.items.last.id, 'past-0');
      expect(api.requests.last.query['direction'], 'previous');
      expect(controller.page.hasPrevious, isTrue);
    },
  );

  test(
    'empty previous page keeps existing lessons and disables further backward navigation',
    () async {
      final api = _TimelineApi()
        ..enqueue(Future.value(_pageJson(['current'])))
        ..enqueue(Future.value(_pageJson([])));
      final controller = StudentLessonTimelineController(
        service: MagicCrmService(api),
        studentId: 'student-1',
      );
      addTearDown(controller.dispose);
      await controller.load();
      await controller.previous();
      expect(controller.page.items.single.id, 'current');
      expect(controller.page.hasPrevious, isFalse);
      expect(controller.error, isNull);
    },
  );

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

  test('loads cursor pages and moves after the final occupied date', () async {
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
      ..enqueue(Future.value(_pageJson(const ['lesson-25', 'lesson-26'])))
      ..enqueue(Future.value(_pageJson(const ['next-period'])));
    final controller = StudentLessonTimelineController(
      service: MagicCrmService(api),
      studentId: 'student-1',
      now: () => DateTime(2026, 9, 9, 17),
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.page.windowStart, DateTime(2026, 9, 6));
    expect(controller.page.items.map((item) => item.id), [
      'lesson-1',
      'lesson-2',
      'lesson-25',
      'lesson-26',
    ]);
    expect(api.requests[1].query['cursor'], 'cursor-next');
    await controller.next();

    expect(controller.page.items.map((item) => item.id), ['next-period']);
    expect(
      api.requests.map((request) => request.path),
      everyElement('/crm/students/student-1/lesson-timeline'),
    );
    expect(api.requests.last.query, {
      'direction': 'next',
      'limit': 40,
      'anchor': DateTime(2026, 9, 5).toUtc().toIso8601String(),
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
