import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/manage_statuses_dialog.dart';

/// Заказчик: «нет кнопки сохранения порядка колонок из раздела настроек колонок
/// канбана». Reorder is now a draft — dragging surfaces «Сохранить порядок», and
/// only tapping it persists the new order.
class _FakeApiClient extends MagicApiClient {
  _FakeApiClient()
      : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<({String path, Object? data})> patches = [];

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    patches.add((path: path, data: data));
    return <String, dynamic>{} as T;
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    return <String, dynamic>{'items': <dynamic>[]} as T;
  }
}

void main() {
  final columns = <Map<String, dynamic>>[
    {'id': 'a', 'label': 'Новый', 'key': 'new', 'color': '#3B82F6'},
    {'id': 'b', 'label': 'Переговоры', 'key': 'talks', 'color': '#F59E0B'},
    {'id': 'c', 'label': 'Отказ', 'key': 'lost', 'color': '#E53935'},
  ];

  testWidgets('reorder shows «Сохранить порядок» and persists on tap',
      (tester) async {
    final fake = _FakeApiClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Scaffold(
            body: ManageStatusesDialog(
              initialColumns: List<Map<String, dynamic>>.from(columns),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No save button until something is actually reordered.
    expect(find.text('Сохранить порядок'), findsNothing);

    // Drag the first column's handle down past the second row.
    final handles = find.byIcon(Icons.drag_indicator_rounded);
    expect(handles, findsNWidgets(3));
    final gesture = await tester.startGesture(tester.getCenter(handles.first));
    await tester.pump(const Duration(milliseconds: 20));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // The reorder is a draft — the save affordance now appears, and nothing was
    // sent yet.
    expect(find.text('Сохранить порядок'), findsOneWidget);
    expect(fake.patches, isEmpty);

    await tester.tap(find.text('Сохранить порядок'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Persisted exactly once, to the order endpoint, with a real reordering of
    // all three columns (drag pixel-distance decides the exact permutation).
    expect(fake.patches.length, 1);
    expect(fake.patches.single.path, '/crm/lead-statuses/order');
    final sentIds = (fake.patches.single.data as Map)['statusIds'] as List;
    expect(sentIds.toSet(), {'a', 'b', 'c'}, reason: 'no column dropped');
    expect(sentIds, isNot(['a', 'b', 'c']), reason: 'order actually changed');

    // The draft affordance is gone once the order is saved.
    await tester.pumpAndSettle();
    expect(find.text('Сохранить порядок'), findsNothing);

    // Let the success toast's auto-dismiss timer fire so no timer outlives the
    // widget tree at teardown.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
