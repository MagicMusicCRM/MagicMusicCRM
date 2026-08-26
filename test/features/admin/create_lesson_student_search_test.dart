import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';

/// Finding a student when creating a lesson.
///
/// Regression: the old picker filtered one capped Student page in memory. The
/// v4 form must delegate every Lead/Student query to the actor-scoped typed
/// `/crm/clients/search` endpoint.

const _branchId = '11111111-1111-1111-1111-111111111111';
const _clientBranchId = '22222222-2222-2222-2222-222222222222';

/// «Зинаида Заречная» is deliberately absent from the initial response, so a
/// test that finds her can only have issued a server query.
class _FakeApiClient extends MagicApiClient {
  _FakeApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<String> searchedQueries = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/clients/resolve') {
      return <String, dynamic>{
            'ref': {
              'type': queryParameters?['type'],
              'id': queryParameters?['id'],
            },
            'label': 'Клиент из карточки',
            'branchId': _clientBranchId,
            'lifecycleState': 'active',
            'tombstone': false,
          }
          as T;
    }
    if (path == '/crm/clients/search') {
      final query = queryParameters?['q']?.toString() ?? '';
      if (query.isNotEmpty) searchedQueries.add(query);
      return <String, dynamic>{
            'items': query.isEmpty
                ? [
                    {
                      'ref': {
                        'type': 'student',
                        'id': '33333333-3333-3333-3333-333333333333',
                      },
                      'label': 'Ученик из первой страницы',
                      'lifecycleState': 'active',
                      'tombstone': false,
                    },
                  ]
                : [
                    {
                      'ref': {
                        'type': 'student',
                        'id': '55555555-5555-5555-5555-555555555555',
                      },
                      'label': 'Зинаида Заречная',
                      'branchId': _clientBranchId,
                      'lifecycleState': 'active',
                      'tombstone': false,
                    },
                  ],
          }
          as T;
    }
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': [
              {
                'id': _branchId,
                'name': 'Главный филиал',
                'utcOffsetMinutes': 0,
              },
              {
                'id': _clientBranchId,
                'name': 'Филиал клиента',
                'utcOffsetMinutes': 0,
              },
            ],
          }
          as T;
    }
    return <String, dynamic>{'items': const []} as T;
  }
}

Widget _host(_FakeApiClient client, {Widget? child}) {
  return ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(client)],
    child: MaterialApp(
      home: Scaffold(body: child ?? const CreateLessonDialog()),
    ),
  );
}

void main() {
  // The dialog formats its date with a ru DateFormat.
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('a student beyond the pre-loaded page is found via the server', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final client = _FakeApiClient();
    await tester.pumpWidget(_host(client));
    await tester.pumpAndSettle();

    // Open the unified typed Client picker.
    await tester.tap(find.byKey(const ValueKey('lesson-client-field')));
    await tester.pumpAndSettle();

    // She is nowhere in the pre-loaded page — the old picker stopped here.
    expect(find.text('Зинаида Заречная'), findsNothing);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('lesson-client-field')),
        matching: find.byType(TextField),
      ),
      'Зинаида',
    );
    // Past the 350 ms search debounce.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      client.searchedQueries,
      contains('Зинаида'),
      reason: 'typing must reach /crm/clients/search, not filter one page',
    );
    final result = find.descendant(
      of: find.byType(Scrollbar).last,
      matching: find.text('Зинаида Заречная'),
    );
    expect(result, findsOneWidget);

    // Picking her must stick even though she was absent from the initial page.
    await tester.tap(result);
    await tester.pumpAndSettle();

    final studentField = find.byKey(const ValueKey('lesson-client-field'));
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: studentField, matching: find.byType(TextField)),
          )
          .controller!
          .text,
      'Зинаида Заречная · Student',
      reason: 'the selected typed client must retain the server label',
    );
    expect(
      find.byKey(const ValueKey('lesson-branch-field:$_clientBranchId')),
      findsOneWidget,
      reason: 'the client card branch must become the lesson default',
    );
    expect(
      find.byKey(const ValueKey('lesson-room-field')),
      findsOneWidget,
      reason: 'the room remains a separate explicit administrator choice',
    );
  });

  testWidgets('a client card lesson starts from the client branch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final client = _FakeApiClient();
    await tester.pumpWidget(
      _host(
        client,
        child: const CreateLessonDialog(
          clientType: 'student',
          clientId: '77777777-7777-7777-7777-777777777777',
          clientName: 'Клиент из карточки',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('lesson-branch-field:$_clientBranchId')),
      findsOneWidget,
    );
    final room = tester.widget<SearchablePickerField>(
      find.byKey(const ValueKey('lesson-room-field')),
    );
    expect(room.selectedId, isNull);
  });
}
