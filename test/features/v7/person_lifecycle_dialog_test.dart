import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/person_lifecycle_dialog.dart';

class PersonLifecycleTestApi extends MagicApiClient {
  PersonLifecycleTestApi({required this.blockers})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<Map<String, dynamic>> blockers;
  Map<String, dynamic>? commandBody;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/teachers/teacher-a/lifecycle-preview') {
      return <String, dynamic>{
            'person': {
              'id': 'teacher-a',
              'type': 'teacher',
              'name': 'Петров Иван',
              'lifecycleState': 'active',
              'version': 4,
            },
            'account': {
              'enabled': true,
              'activeSessions': 2,
              'activeOverrides': 1,
            },
            'impact': {
              'futureLessons': blockers.isEmpty ? 0 : 2,
              'activeSeries': 0,
              'activeGroups': 0,
              'openTasks': 0,
              'activeLeads': 0,
            },
            'blockers': blockers,
          }
          as T;
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
    if (path == '/crm/teachers/teacher-a/offboard') {
      commandBody = Map<String, dynamic>.from(data! as Map);
      return <String, dynamic>{'replayed': false} as T;
    }
    throw StateError('Unexpected POST $path');
  }
}

Future<void> pumpPersonLifecycle(
  WidgetTester tester,
  PersonLifecycleTestApi api,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showPersonLifecycleDialog(
                context,
                personType: 'teacher',
                personId: 'teacher-a',
                personName: 'Петров Иван',
              ),
              child: const Text('Открыть'),
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
  testWidgets('person offboarding stays blocked while future work exists', (
    tester,
  ) async {
    final api = PersonLifecycleTestApi(
      blockers: const [
        {
          'code': 'FUTURE_LESSONS',
          'count': 2,
          'message': 'Переназначьте будущие занятия.',
        },
      ],
    );
    await pumpPersonLifecycle(tester, api);

    expect(find.text('Занятия: 2'), findsOneWidget);
    expect(
      find.textContaining('Переназначьте будущие занятия.'),
      findsOneWidget,
    );
    final commit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Отключить и архивировать'),
    );
    expect(commit.onPressed, isNull);
  });

  testWidgets('safe offboarding sends version, reason and confirmation', (
    tester,
  ) async {
    final api = PersonLifecycleTestApi(blockers: const []);
    await pumpPersonLifecycle(tester, api);

    await tester.enterText(
      find.widgetWithText(TextField, 'Причина отключения *'),
      'Завершение трудовых отношений',
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Отключить и архивировать'),
    );
    await tester.pumpAndSettle();

    expect(api.commandBody, {
      'expectedVersion': 4,
      'reasonText': 'Завершение трудовых отношений',
      'confirm': true,
    });
  });
}
