import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/user_roles_widget.dart';

void main() {
  testWidgets('server search keeps the loaded list while the request runs', (
    tester,
  ) async {
    final api = _SearchApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: UserRolesWidget(currentRole: 'manager')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Тестова Анна'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Анна');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Тестова Анна'), findsOneWidget);
    expect(find.byType(ListSkeleton), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    api.releaseSearch();
    await tester.pumpAndSettle();
  });
}

class _SearchApi extends MagicApiClient {
  _SearchApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final _searchGate = Completer<void>();

  void releaseSearch() => _searchGate.complete();

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path != '/admin/profiles') {
      return <String, dynamic>{'items': const []} as T;
    }
    if ((queryParameters?['q']?.toString() ?? '').isNotEmpty) {
      await _searchGate.future;
    }
    return <String, dynamic>{
          'items': [
            {
              'id': 'profile-1',
              'userId': 'user-1',
              'firstName': 'Анна',
              'lastName': 'Тестова',
              'email': 'anna@example.com',
              'role': 'manager',
            },
          ],
        }
        as T;
  }
}
