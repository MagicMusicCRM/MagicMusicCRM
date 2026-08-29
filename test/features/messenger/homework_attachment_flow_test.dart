import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/homework_attachment_widgets.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/homework_widget.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_sheets.dart';

import '../crm/client_card/card_fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('assignment sheet returns lesson and selected file', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _SheetHarness(
            picker: (_) async => HomeworkPickedFile(
              bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 test')),
              name: 'этюд.pdf',
              size: 13,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Новый этюд');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final pickAttachment = find.byKey(
      const ValueKey('homework-pick-attachment'),
    );
    await tester.ensureVisible(pickAttachment);
    await tester.pumpAndSettle();
    await tester.tap(pickAttachment);
    await tester.pumpAndSettle();

    expect(find.text('этюд.pdf'), findsOneWidget);
    expect(find.byKey(const ValueKey('homework-lesson')), findsOneWidget);

    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();

    expect(find.text('lesson-a|этюд.pdf'), findsOneWidget);
  });

  testWidgets('client sees downloadable files and submission choices', (
    tester,
  ) async {
    final adapter = _HomeworkAdapter();
    final crm = MagicCrmService(_client(adapter));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicCrmServiceProvider.overrideWithValue(crm),
          crmRealtimeProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 700,
              child: HomeworkWidget(studentId: 'student-a'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Материал.pdf'), findsOneWidget);
    expect(find.text('Решение.txt'), findsOneWidget);
    expect(find.text('Задание'), findsOneWidget);
    expect(find.text('Решение'), findsOneWidget);

    await tester.tap(find.text('Сдать'));
    await tester.pumpAndSettle();

    expect(find.text('Добавить ещё файл'), findsOneWidget);
    expect(find.text('Сдать прикреплённое решение'), findsOneWidget);
  });

  testWidgets('staff progress shows homework files and retry action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(
      role: 'manager',
      student: const {
        'id': 'student-a',
        'firstName': 'Анна',
        'lastName': 'Смирнова',
        'status': 'active',
        'branchId': 'branch-a',
        'branchName': 'Главный',
      },
      homeworks: const [
        {
          'id': 'homework-a',
          'studentId': 'student-a',
          'title': 'Гаммы',
          'status': 'assigned',
          'createdAt': '2026-08-11T12:00:00.000Z',
          'attachments': [
            {
              'id': 'attachment-a',
              'fileId': 'file-a',
              'fileName': 'Материал препода.pdf',
              'mimeType': 'application/pdf',
              'sizeBytes': 2048,
              'kind': 'assignment',
            },
          ],
        },
      ],
    );

    await pumpClientCard(
      tester,
      api: api,
      seed: const {
        'id': 'student-a',
        'firstName': 'Анна',
        'lastName': 'Смирнова',
        'status': 'active',
        'branchId': 'branch-a',
        'branchName': 'Главный',
      },
      entityType: 'student',
      routed: true,
    );

    final progress = find.byKey(const Key('client-section-jump-progress'));
    await tester.ensureVisible(progress);
    await tester.tap(progress);
    await tester.pumpAndSettle();

    expect(find.text('Материал препода.pdf'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('homework-attach-homework-a')),
      findsOneWidget,
    );
  });
}

class _SheetHarness extends StatefulWidget {
  const _SheetHarness({required this.picker});

  final Future<HomeworkPickedFile?> Function(BuildContext) picker;

  @override
  State<_SheetHarness> createState() => _SheetHarnessState();
}

class _SheetHarnessState extends State<_SheetHarness> {
  String _result = '';

  Future<void> _open() async {
    final result = await showAssignHomeworkSheet(
      context,
      recentHomeworks: const [],
      lessons: const [
        {
          'id': 'lesson-a',
          'scheduled_at': '2026-08-11T12:00:00.000Z',
          'teacher_name': 'Анна Иванова',
        },
      ],
      requireLesson: true,
      pickAttachment: widget.picker,
    );
    if (result == null || !mounted) return;
    setState(() {
      _result = '${result.lessonId}|${result.attachment?.name}';
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ElevatedButton(onPressed: _open, child: const Text('Открыть')),
      Text(_result),
    ],
  );
}

MagicApiClient _client(HttpClientAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.example.test/api',
      validateStatus: (status) => status != null && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return MagicApiClient(
    baseUrl: 'https://api.example.test/api',
    tokenStore: MemoryMagicTokenStore(),
    dio: dio,
  );
}

class _HomeworkAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.method, 'GET');
    expect(options.uri.path, '/api/crm/homeworks');
    return ResponseBody.fromString(
      jsonEncode({
        'items': [
          {
            'id': 'homework-a',
            'studentId': 'student-a',
            'title': 'Гаммы',
            'status': 'assigned',
            'attachments': [
              {
                'id': 'attachment-a',
                'fileId': 'file-a',
                'fileName': 'Материал.pdf',
                'mimeType': 'application/pdf',
                'sizeBytes': 2048,
                'kind': 'assignment',
              },
              {
                'id': 'attachment-b',
                'fileId': 'file-b',
                'fileName': 'Решение.txt',
                'mimeType': 'text/plain',
                'sizeBytes': 120,
                'kind': 'submission',
              },
            ],
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
