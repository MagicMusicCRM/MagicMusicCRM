import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/auth/data/models/release_gate_models.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';

/// Контракты 1/2 (правки №2, п.6) в диалоге занятия:
///
/// 1. Предсейв-проверка `/crm/schedule/conflicts`: занятый педагог БЛОКИРУЕТ
///    сохранение и показывает, кто/когда/где уже стоит в слоте.
/// 2. «Всё равно назначить» доступно только admin+ и повторяет запрос с
///    `force: true`.
/// 3. Тумблер «Пробное занятие» доезжает до тела POST /crm/lessons
///    (`isTrial: true`).

const _teacherId = '22222222-2222-2222-2222-222222222222';
const _studentId = '33333333-3333-3333-3333-333333333333';
const _branchId = '11111111-1111-1111-1111-111111111111';

Map<String, dynamic> _busyResponse() => {
  'teacherBusy': true,
  'roomBusy': false,
  'conflicts': [
    {
      'lessonId': '44444444-4444-4444-4444-444444444444',
      'title': 'Мария Занятова',
      'startsAt': '2026-07-18T07:00:00.000Z',
      'endsAt': '2026-07-18T08:00:00.000Z',
      'roomName': 'Зал 1',
      'teacherName': 'Пётр Педагогов',
    },
  ],
};

Map<String, dynamic> _freeResponse() => {
  'teacherBusy': false,
  'roomBusy': false,
  'conflicts': const [],
};

class _FakeApiClient extends MagicApiClient {
  _FakeApiClient({required this.conflictsResponse})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  Map<String, dynamic> conflictsResponse;
  final List<Map<String, dynamic>> conflictsQueries = [];
  final List<Map<String, dynamic>> lessonPosts = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    switch (path) {
      case '/crm/teachers':
        return <String, dynamic>{
              'items': [
                {
                  'id': _teacherId,
                  'firstName': 'Пётр',
                  'lastName': 'Педагогов',
                  'status': 'active',
                },
              ],
            }
            as T;
      case '/crm/students':
        return <String, dynamic>{
              'items': [
                {
                  'id': _studentId,
                  'firstName': 'Иван',
                  'lastName': 'Прилежный',
                  'status': 'active',
                },
              ],
            }
            as T;
      case '/crm/branches':
        return <String, dynamic>{
              'items': [
                {
                  'id': _branchId,
                  'name': 'Главный филиал',
                  'utcOffsetMinutes': 180,
                },
              ],
            }
            as T;
      case '/crm/schedule/conflicts':
        conflictsQueries.add(
          Map<String, dynamic>.from(queryParameters ?? const {}),
        );
        return conflictsResponse as T;
    }
    return <String, dynamic>{'items': const []} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/lessons') {
      lessonPosts.add(Map<String, dynamic>.from(data as Map));
      return <String, dynamic>{'id': 'lesson-1'} as T;
    }
    throw UnimplementedError('POST $path');
  }
}

Widget _host(_FakeApiClient client, {String role = 'admin'}) {
  return ProviderScope(
    overrides: [
      magicApiClientProvider.overrideWithValue(client),
      releaseGateStatusProvider.overrideWith(
        (ref) async => ReleaseGateStatus(
          role: role,
          profileComplete: true,
          legalAccepted: true,
          deletionPending: false,
        ),
      ),
    ],
    // Диалог открывается штатным CreateLessonDialog.show(...): успешное
    // сохранение делает Navigator.pop(true), и без настоящего диалогового
    // роута оно выкинуло бы домашний экран теста.
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => CreateLessonDialog.show(ctx),
              child: const Text('открыть диалог'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _fillRequired(WidgetTester tester) async {
  await tester.tap(find.text('Преподаватель *'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Пётр Педагогов').last);
  await tester.pumpAndSettle();

  await tester.tap(find.text('Ученик *'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Иван Прилежный').last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  // Скрытые ассерты вёрстки топятся дефолтным вьюпортом 800×600 — берём
  // большой, как в остальных тестах диалога.
  Future<void> pumpHost(
    WidgetTester tester,
    _FakeApiClient client, {
    String role = 'admin',
  }) async {
    tester.view.physicalSize = const Size(1400, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(client, role: role));
    await tester.pumpAndSettle();
    await tester.tap(find.text('открыть диалог'));
    await tester.pumpAndSettle();
  }

  // Пока открыт диалог конфликтов, за ним крутится спиннер «Сохранение» —
  // pumpAndSettle никогда не успокоится, поэтому качаем кадры руками.
  Future<void> tapCreate(WidgetTester tester) async {
    await tester.tap(find.text('Создать'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('занятый педагог блокирует сохранение и показывает конфликт', (
    tester,
  ) async {
    final client = _FakeApiClient(conflictsResponse: _busyResponse());
    await pumpHost(tester, client);
    await _fillRequired(tester);

    await tapCreate(tester);

    // Предсейв-проверка сходила на /crm/schedule/conflicts с педагогом.
    expect(client.conflictsQueries, hasLength(1));
    expect(client.conflictsQueries.single['teacherId'], _teacherId);

    // Конфликт показан: заголовок + кто/когда/где.
    expect(find.text('Время занято'), findsOneWidget);
    expect(find.text('Преподаватель занят в это время'), findsOneWidget);
    expect(find.textContaining('Мария Занятова'), findsOneWidget);
    expect(find.textContaining('Зал 1'), findsOneWidget);

    // Сохранение ЗАБЛОКИРОВАНО — POST не ушёл.
    expect(client.lessonPosts, isEmpty);

    // «Отмена» закрывает диалог, POST так и не уходит.
    await tester.tap(find.text('Отмена').last);
    await tester.pumpAndSettle();
    expect(client.lessonPosts, isEmpty);
    expect(find.text('Время занято'), findsNothing);
  });

  testWidgets('admin подтверждает «Всё равно назначить» → POST c force: true', (
    tester,
  ) async {
    final client = _FakeApiClient(conflictsResponse: _busyResponse());
    await pumpHost(tester, client);
    await _fillRequired(tester);

    await tapCreate(tester);

    await tester.tap(find.text('Всё равно назначить'));
    await tester.pumpAndSettle();

    expect(client.lessonPosts, hasLength(1));
    final body = client.lessonPosts.single;
    expect(body['force'], isTrue);
    expect(body['teacherId'], _teacherId);
    expect(body['studentId'], _studentId);
  });

  testWidgets('не-admin не видит кнопку force при конфликте', (tester) async {
    final client = _FakeApiClient(conflictsResponse: _busyResponse());
    await pumpHost(tester, client, role: 'teacher');
    await _fillRequired(tester);

    await tapCreate(tester);

    expect(find.text('Время занято'), findsOneWidget);
    expect(find.text('Всё равно назначить'), findsNothing);
    expect(client.lessonPosts, isEmpty);

    await tester.tap(find.text('Отмена').last);
    await tester.pumpAndSettle();
    expect(client.lessonPosts, isEmpty);
  });

  testWidgets('тумблер «Пробное занятие» доезжает до тела POST', (
    tester,
  ) async {
    final client = _FakeApiClient(conflictsResponse: _freeResponse());
    await pumpHost(tester, client);
    await _fillRequired(tester);

    await tester.ensureVisible(find.text('Пробное занятие'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Пробное занятие'));
    await tester.pumpAndSettle();

    await tapCreate(tester);
    await tester.pumpAndSettle();

    expect(client.lessonPosts, hasLength(1));
    final body = client.lessonPosts.single;
    expect(body['isTrial'], isTrue);
    // Свободный слот — force не отправляется вовсе.
    expect(body.containsKey('force'), isFalse);
  });
}
