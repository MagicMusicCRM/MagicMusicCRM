import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/group_lifecycle_dialog.dart';

class GroupLifecycleTestApi extends MagicApiClient {
  GroupLifecycleTestApi({required this.blockers})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<Map<String, dynamic>> blockers;
  Map<String, dynamic>? archiveBody;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/groups/group-a/history') {
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
    if (path == '/crm/groups/group-a/archive-preview') {
      return <String, dynamic>{
            'group': {
              'id': 'group-a',
              'name': 'Вокальный ансамбль',
              'lifecycleState': 'active',
              'version': 1,
            },
            'canArchive': blockers.isEmpty,
            'canRestore': false,
            'blockers': blockers,
            'impact': const {
              'operational': {'activeMembers': 6},
              'preservedHistory': {
                'memberships': 8,
                'lessons': 42,
                'completedLessons': 34,
                'endedSeries': 2,
                'endedPlans': 1,
              },
            },
          }
          as T;
    }
    if (path == '/crm/groups/group-a/archive') {
      archiveBody = Map<String, dynamic>.from(data! as Map);
      return <String, dynamic>{
            'group': {
              'id': 'group-a',
              'lifecycleState': 'archived',
              'version': 2,
            },
          }
          as T;
    }
    throw StateError('Unexpected POST $path');
  }
}

Future<void> pumpGroupLifecycleDialog(
  WidgetTester tester,
  GroupLifecycleTestApi api,
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
                  builder: (_) => const GroupLifecycleDialog(
                    group: {
                      'id': 'group-a',
                      'name': 'Вокальный ансамбль',
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
  testWidgets('group completion is blocked by a future lesson', (tester) async {
    final api = GroupLifecycleTestApi(
      blockers: const [
        {
          'code': 'FUTURE_LESSONS',
          'label': 'Будущие занятия',
          'count': 2,
          'remediation': 'Перенесите или отмените будущие занятия группы.',
        },
      ],
    );
    await pumpGroupLifecycleDialog(tester, api);

    expect(find.text('Сначала завершите активные сценарии'), findsOneWidget);
    expect(find.text('Будущие занятия: 2'), findsOneWidget);
    final commit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Завершить'),
    );
    expect(commit.onPressed, isNull);
  });

  testWidgets('safe completion sends version and preserves roster messaging', (
    tester,
  ) async {
    final api = GroupLifecycleTestApi(blockers: const []);
    await pumpGroupLifecycleDialog(tester, api);

    expect(
      find.textContaining('Состав (6) и все финансовые факты'),
      findsOneWidget,
    );
    expect(find.text('Записей состава: 8'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина завершения *'),
      'Учебный год завершён',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Завершить'));
    await tester.pumpAndSettle();

    expect(api.archiveBody, {
      'expectedVersion': 1,
      'confirm': true,
      'reasonText': 'Учебный год завершён',
      'effectiveDate': isA<String>(),
    });
    expect(find.byType(GroupLifecycleDialog), findsNothing);
  });
}
