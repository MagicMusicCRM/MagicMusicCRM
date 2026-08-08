import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/admin/presentation/screens/profile_detail_screen.dart';

class _ProfileApi extends MagicApiClient {
  _ProfileApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/admin/profiles/profile-1') {
      return <String, dynamic>{
            'id': 'profile-1',
            'userId': 'user-1',
            'email': 'client@example.test',
            'role': 'client',
            'firstName': 'Анна',
            'lastName': 'Смирнова',
          }
          as T;
    }
    if (path == '/admin/profiles/profile-1/links') {
      throw StateError('links unavailable');
    }
    throw UnimplementedError(path);
  }
}

void main() {
  testWidgets('profile stays actionable and does not hide a links failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(_ProfileApi()),
          capabilitySnapshotProvider.overrideWith(
            (ref) async => const CapabilitySnapshot(
              accountId: 'manager-1',
              role: 'manager',
              accessVersion: 1,
              capabilities: {'system.settings.manage'},
              scopes: {},
            ),
          ),
        ],
        child: const MaterialApp(
          home: ProfileDetailScreen(profileId: 'profile-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Смирнова Анна'), findsOneWidget);
    expect(find.text('Настроить доступ'), findsOneWidget);
    expect(find.text('Связать по телефону'), findsOneWidget);
    expect(find.text('Не удалось загрузить привязки'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
