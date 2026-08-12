import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/branch_form_dialog.dart';

class _BranchFormApi extends MagicApiClient {
  _BranchFormApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  Map<String, dynamic>? body;

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path != '/crm/branches') throw StateError('Unexpected POST $path');
    body = Map<String, dynamic>.from(data! as Map);
    return <String, dynamic>{
          'id': 'branch-a',
          'name': body!['name'],
          'utcOffsetMinutes': body!['utcOffsetMinutes'],
        }
        as T;
  }
}

void main() {
  testWidgets('new branch requires and submits working hours', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _BranchFormApi();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: Scaffold(body: BranchFormDialog())),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Название *'),
      'Сокол',
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    expect(find.text('Укажите рабочие часы хотя бы для одного дня'), findsOne);
    expect(api.body, isNull);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(api.body, isNotNull);
    expect(api.body!['weeklyHours'], [
      {'weekday': 1, 'open': '09:00', 'close': '21:00'},
    ]);
  });
}
