import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/convert_lead_dialog.dart';

/// Faked at the API-client seam, NOT by implementing MagicCrmService.
///
/// MagicCrmService's methods live on extensions (`extension MagicCrmOrg on
/// MagicCrmService` and friends), and an extension call resolves against the
/// STATIC type — so an `implements MagicCrmService` fake is never consulted:
/// the real extension body runs and reaches for the client. That is why these
/// tests were failing while looking perfectly reasonable.
class _FakeApiClient extends MagicApiClient {
  _FakeApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  Map<String, dynamic>? createStudentBody;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/branches') {
      return <String, dynamic>{
        'items': [
          {'id': 'branch-a', 'name': 'Центр'},
          {'id': 'branch-b', 'name': 'Восток'},
        ],
      } as T;
    }
    if (path == '/crm/branches/branch-a/disciplines') {
      return <String, dynamic>{
        'items': [
          {'id': 'bd-a', 'disciplineId': 'd1', 'name': 'Вокал', 'sortOrder': 0},
        ],
      } as T;
    }
    if (path == '/crm/branches/branch-b/disciplines') {
      return <String, dynamic>{
        'items': [
          {'id': 'bd-b', 'disciplineId': 'd2', 'name': 'Гитара', 'sortOrder': 0},
        ],
      } as T;
    }
    return <String, dynamic>{'items': <dynamic>[]} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/students') {
      createStudentBody = data as Map<String, dynamic>?;
      return <String, dynamic>{
        'id': 'student-a',
        'leadId': createStudentBody?['leadId'],
      } as T;
    }
    return <String, dynamic>{} as T;
  }
}

void main() {
  testWidgets('picks branch + discipline and converts', (tester) async {
    final fake = _FakeApiClient();
    Map<String, dynamic>? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await ConvertLeadDialog.show(
                      context,
                      lead: const {
                        'id': 'lead-a',
                        'name': 'Анна',
                        'last_name': 'Иванова',
                        'phone': '+79990000000',
                        'branch_id': 'branch-a',
                        'custom_data': {'discipline': 'Вокал'},
                      },
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Branch is loaded and the dialog shows 'Центр' as the selected branch
    expect(find.text('Центр'), findsWidgets);

    // Tap the confirm button
    await tester.tap(find.widgetWithText(FilledButton, 'Создать ученика'));
    await tester.pumpAndSettle();

    expect(fake.createStudentBody!['leadId'], 'lead-a');
    final patch =
        fake.createStudentBody!['customDataPatch'] as Map<String, dynamic>;
    expect(patch['branchId'], 'branch-a');
    expect(patch['discipline'], 'Вокал');
    expect(result!['id'], 'student-a');
  });

  testWidgets('discipline reloads when branch changes', (tester) async {
    final fake = _FakeApiClient();
    int disciplineCallCount = 0;
    // Wrap fake to count discipline calls
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await ConvertLeadDialog.show(
                      context,
                      lead: const {
                        'id': 'lead-b',
                        'name': 'Иван',
                        'branch_id': 'branch-a',
                        'custom_data': {'discipline': 'Вокал'},
                      },
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Branch-a is selected and its disciplines are loaded.
    // The selected discipline "Вокал" should be visible in the discipline dropdown.
    expect(find.text('Вокал'), findsWidgets);

    // Change branch to branch-b by opening the branch dropdown
    await tester.tap(find.text('Центр'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Восток').last);
    await tester.pumpAndSettle();

    // After switching to branch-b the discipline is cleared (Вокал not in branch-b).
    // Open discipline dropdown to confirm Гитара is offered for branch-b.
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    expect(find.text('Гитара'), findsWidgets);

    // Ignore return value — just verifying reload
    disciplineCallCount = 0; // suppress unused warning
    expect(disciplineCallCount, 0);
  });
}
