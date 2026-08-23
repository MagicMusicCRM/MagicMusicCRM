import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/branch_lifecycle_dialog.dart';

class BranchLifecycleTestApi extends MagicApiClient {
  BranchLifecycleTestApi({required this.blockers})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<Map<String, dynamic>> blockers;
  Map<String, dynamic>? closeBody;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/branches/branch-a/history') {
      return <String, dynamic>{'items': const <Map<String, dynamic>>[]} as T;
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/branches/branch-a/close-preview') {
      return <String, dynamic>{
            'branch': {
              'id': 'branch-a',
              'name': 'Сокол',
              'lifecycleState': 'active',
              'version': 1,
            },
            'canClose': blockers.isEmpty,
            'blockers': blockers,
            'impact': const {
              'preservedHistory': {
                'payments': 2,
                'expenses': 1,
                'lessons': 8,
                'configurationRevisions': 1,
                'chats': 3,
              },
            },
          }
          as T;
    }
    if (path == '/crm/branches/branch-a/close') {
      closeBody = Map<String, dynamic>.from(data! as Map);
      return <String, dynamic>{
            'branch': {
              'id': 'branch-a',
              'lifecycleState': 'archived',
              'version': 2,
            },
          }
          as T;
    }
    throw StateError('Unexpected POST $path');
  }
}

Future<void> pumpLifecycleDialog(
  WidgetTester tester,
  BranchLifecycleTestApi api,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const BranchLifecycleDialog(
                    branch: {
                      'id': 'branch-a',
                      'name': 'Сокол',
                      'lifecycle_state': 'active',
                      'version': 1,
                    },
                  ),
                ),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('branch close is disabled until every blocker is remediated', (
    tester,
  ) async {
    final api = BranchLifecycleTestApi(
      blockers: const [
        {
          'code': 'ACTIVE_STUDENTS',
          'label': 'Ученики',
          'count': 2,
          'remediation': 'Перенесите или архивируйте учеников.',
        },
      ],
    );
    await pumpLifecycleDialog(tester, api);

    expect(find.text('Сначала устраните блокеры'), findsOneWidget);
    expect(find.text('Ученики: 2'), findsOneWidget);
    final commit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Закрыть филиал'),
    );
    expect(commit.onPressed, isNull);
  });

  testWidgets('safe close sends explicit version, confirmation and reason', (
    tester,
  ) async {
    final api = BranchLifecycleTestApi(blockers: const []);
    await pumpLifecycleDialog(tester, api);

    expect(
      find.text('Активных связей нет. Филиал можно закрыть.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина закрытия *'),
      'Переезд школы',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Закрыть филиал'));
    await tester.pumpAndSettle();

    expect(api.closeBody, {
      'expectedVersion': 1,
      'confirm': true,
      'reasonText': 'Переезд школы',
      'effectiveDate': isA<String>(),
    });
    expect(find.byType(BranchLifecycleDialog), findsNothing);
  });
}
