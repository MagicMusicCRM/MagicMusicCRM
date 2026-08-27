import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/reference_catalog_lifecycle_dialog.dart';

class ReferenceLifecycleTestApi extends MagicApiClient {
  ReferenceLifecycleTestApi({
    required this.blockers,
    this.activeStudents = 0,
    this.history = const [
      {'operation': 'rename', 'reasonText': 'Первичное название'},
    ],
    this.renameError,
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<Map<String, dynamic>> blockers;
  final int activeStudents;
  final List<Map<String, dynamic>> history;
  final Object? renameError;
  String name = 'Вокал';
  int version = 1;
  Map<String, dynamic>? archiveBody;
  Map<String, dynamic>? renameBody;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/disciplines/discipline-a/history') {
      return <String, dynamic>{'items': history} as T;
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
    if (path == '/crm/disciplines/discipline-a/lifecycle-preview') {
      return <String, dynamic>{
            'entity': {
              'id': 'discipline-a',
              'name': name,
              'lifecycleState': 'active',
              'version': version,
            },
            'canArchive': blockers.isEmpty,
            'canRestore': false,
            'canRename': true,
            'blockers': blockers,
            'impact': {'activeStudents': activeStudents, 'activeTeachers': 0},
          }
          as T;
    }
    if (path == '/crm/disciplines/discipline-a/archive') {
      archiveBody = Map<String, dynamic>.from(data! as Map);
      return <String, dynamic>{
            'preview': {
              'entity': {
                'id': 'discipline-a',
                'lifecycleState': 'archived',
                'version': version + 1,
              },
            },
          }
          as T;
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/disciplines/discipline-a') {
      renameBody = Map<String, dynamic>.from(data! as Map);
      if (renameError != null) throw renameError!;
      name = renameBody!['name'] as String;
      version += 1;
      return <String, dynamic>{
            'preview': {
              'entity': {
                'id': 'discipline-a',
                'name': name,
                'lifecycleState': 'active',
                'version': version,
              },
            },
          }
          as T;
    }
    throw StateError('Unexpected PATCH $path');
  }
}

Future<void> pumpReferenceLifecycleDialog(
  WidgetTester tester,
  ReferenceLifecycleTestApi api,
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
                  builder: (_) => const ReferenceCatalogLifecycleDialog(
                    entityType: 'discipline',
                    item: {
                      'id': 'discipline-a',
                      'name': 'Вокал',
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
  testWidgets('discipline usage is visible impact and does not block archive', (
    tester,
  ) async {
    final api = ReferenceLifecycleTestApi(
      blockers: const [],
      activeStudents: 2,
    );
    await pumpReferenceLifecycleDialog(tester, api);

    expect(find.text('Сначала устраните блокеры'), findsNothing);
    expect(find.text('activeStudents: 2'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('reference-reason-field')),
      'Информационная дисциплина больше не используется',
    );
    await tester.pump();
    final commit = tester.widget<FilledButton>(
      find.byKey(const ValueKey('reference-lifecycle-button')),
    );
    expect(commit.onPressed, isNotNull);
  });

  testWidgets('safe archive sends explicit version, confirmation and reason', (
    tester,
  ) async {
    final api = ReferenceLifecycleTestApi(blockers: const []);
    await pumpReferenceLifecycleDialog(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey('reference-reason-field')),
      'Направление больше не используется',
    );
    await tester.tap(find.byKey(const ValueKey('reference-lifecycle-button')));
    await tester.pumpAndSettle();

    expect(api.archiveBody, {
      'expectedVersion': 1,
      'confirm': true,
      'reasonText': 'Направление больше не используется',
    });
    expect(find.byType(ReferenceCatalogLifecycleDialog), findsNothing);
  });

  testWidgets('rename stays in the dialog and advances the entity version', (
    tester,
  ) async {
    final api = ReferenceLifecycleTestApi(blockers: const []);
    await pumpReferenceLifecycleDialog(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey('reference-name-field')),
      'Эстрадный вокал',
    );
    await tester.enterText(
      find.byKey(const ValueKey('reference-reason-field')),
      'Уточнение названия',
    );
    await tester.tap(find.byKey(const ValueKey('rename-reference-button')));
    await tester.pumpAndSettle();

    expect(api.renameBody, {
      'name': 'Эстрадный вокал',
      'expectedVersion': 1,
      'confirm': true,
      'reasonText': 'Уточнение названия',
    });
    expect(api.version, 2);
    expect(find.byType(ReferenceCatalogLifecycleDialog), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('reference-name-field')),
    );
    expect(field.controller!.text, 'Эстрадный вокал');
  });

  testWidgets('rejected rename restores the canonical name in the field', (
    tester,
  ) async {
    final api = ReferenceLifecycleTestApi(
      blockers: const [],
      renameError: const MagicApiException(
        statusCode: 409,
        message: 'VERSION_CONFLICT',
      ),
    );
    await pumpReferenceLifecycleDialog(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey('reference-name-field')),
      'Отклонённое имя',
    );
    await tester.enterText(
      find.byKey(const ValueKey('reference-reason-field')),
      'Уточнение названия',
    );
    await tester.tap(find.byKey(const ValueKey('rename-reference-button')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('reference-name-field')),
    );
    expect(field.controller!.text, 'Вокал');
  });

  testWidgets(
    'history reports the full count but renders at most ten entries',
    (tester) async {
      final api = ReferenceLifecycleTestApi(
        blockers: const [],
        history: List.generate(
          12,
          (index) => {
            'operation': 'rename',
            'reasonText': 'Изменение ${index + 1}',
          },
        ),
      );
      await pumpReferenceLifecycleDialog(tester, api);

      expect(find.text('История (12)'), findsOneWidget);
      await tester.tap(find.text('История (12)'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.history_rounded), findsNWidgets(10));
      expect(find.text('Изменение 10'), findsOneWidget);
      expect(find.text('Изменение 11'), findsNothing);
    },
  );
}
