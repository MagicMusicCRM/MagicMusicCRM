import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';

/// Finding a student when creating a lesson.
///
/// Regression: the picker was handed `listStudents(limit: 100)` and filtered
/// that list in memory, so any student past the first page could not be found —
/// however exactly their name was typed. The school has ~1000 students, so the
/// search silently covered a tenth of them. `/crm/students/search` (pg_trgm,
/// ranked, phone + custom_data aware) already existed; the picker just never
/// called it.

const _branchId = '11111111-1111-1111-1111-111111111111';

/// Fake API that mirrors the real split: `/crm/students` serves ONE capped page
/// and `/crm/students/search` is the only thing that sees the whole table.
/// «Зинаида Заречная» is deliberately absent from the page, so a test that
/// finds her can only have gone to the server.
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
    if (path == '/crm/students') {
      return <String, dynamic>{
        'items': [
          for (var i = 1; i <= 100; i++)
            {
              'id': 'student-$i',
              'firstName': 'Ученик',
              'lastName': '$i',
              'status': 'active',
            },
        ],
      } as T;
    }
    if (path == '/crm/students/search') {
      searchedQueries.add(queryParameters?['q']?.toString() ?? '');
      return <String, dynamic>{
        'items': [
          {
            'id': 'student-501',
            'firstName': 'Зинаида',
            'lastName': 'Заречная',
            'status': 'active',
          },
        ],
        'totalCount': 1,
      } as T;
    }
    if (path == '/crm/branches') {
      return <String, dynamic>{
        'items': [
          {'id': _branchId, 'name': 'Главный филиал', 'utcOffsetMinutes': 0},
        ],
      } as T;
    }
    return <String, dynamic>{'items': const []} as T;
  }
}

Widget _host(_FakeApiClient client) {
  return ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(client)],
    child: const MaterialApp(home: Scaffold(body: CreateLessonDialog())),
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

    // Open the student picker.
    await tester.tap(find.text('Ученик *'));
    await tester.pumpAndSettle();

    // She is nowhere in the pre-loaded page — the old picker stopped here.
    expect(find.text('Зинаида Заречная'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'Зинаида');
    // Past the 350 ms search debounce.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      client.searchedQueries,
      contains('Зинаида'),
      reason: 'typing must reach /crm/students/search, not filter one page',
    );
    expect(find.text('Зинаида Заречная'), findsOneWidget);

    // Picking her must stick. The field renders the name out of the pre-loaded
    // page, so a server-found student used to select and then display as «Не
    // выбран» — the pick looked like it silently failed.
    await tester.tap(find.text('Зинаида Заречная'));
    await tester.pumpAndSettle();

    // The sheet is gone, so the surviving name is the one the field renders.
    final studentField = find
        .ancestor(of: find.text('Ученик *'), matching: find.byType(Column))
        .first;
    expect(
      find.descendant(
        of: studentField,
        matching: find.text('Зинаида Заречная'),
      ),
      findsOneWidget,
      reason: 'the field reads names out of the pre-loaded page, so a '
          'server-found student would select and then display «Не выбран»',
    );
  });
}
