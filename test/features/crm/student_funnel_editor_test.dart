import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/student_funnel_editor.dart';

class _FunnelApi extends MagicApiClient {
  _FunnelApi({
    this.failPublish = false,
    this.empty = false,
    this.canonicalLabelAfterPublish,
    this.failReloadAfterMutation = false,
    this.withHistory = false,
  }) : schoolVersion = empty ? 0 : 1,
       super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool failPublish;
  final bool empty;
  final String? canonicalLabelAfterPublish;
  final bool failReloadAfterMutation;
  final bool withHistory;
  int schoolVersion;
  int publishCalls = 0;
  int rollbackCalls = 0;
  String? publishedLabel;
  Map<String, dynamic>? published;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/client-pipelines') {
      if (failReloadAfterMutation && publishCalls + rollbackCalls > 0) {
        throw StateError('canonical reload failed');
      }
      return <String, dynamic>{
            'clientType': queryParameters?['clientType'],
            'branchId': queryParameters?['branchId'],
            'source': 'school',
            'schoolVersion': schoolVersion,
            'branchVersion': 0,
            'stages': empty && schoolVersion == 0
                ? const <Map<String, dynamic>>[]
                : [
                    {
                      'key': 'active',
                      'label':
                          publishedLabel ??
                          (queryParameters?['clientType'] == 'lead'
                              ? 'Новый лид'
                              : 'Обучается'),
                      'style': 'green',
                      'active': true,
                      'allowedTransitions': const <String>[],
                    },
                  ],
            'remediationStatuses': const <Map<String, dynamic>>[],
          }
          as T;
    }
    if (path == '/crm/client-pipelines/revisions') {
      return <String, dynamic>{
            'items': empty
                ? const <Map<String, dynamic>>[]
                : withHistory
                ? [
                    {'version': schoolVersion, 'reason': 'Текущая версия'},
                    {'version': 0, 'reason': 'Исходная версия'},
                  ]
                : [
                    {'version': schoolVersion, 'reason': 'Системная версия'},
                  ],
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
    if (path == '/crm/client-pipelines/preview') {
      return <String, dynamic>{
            'valid': true,
            'changes': {'created': 0, 'updated': 1, 'archived': 0},
            'affectedClients': 0,
            'blockingIssues': <dynamic>[],
          }
          as T;
    }
    if (path == '/crm/client-pipelines/publish') {
      published = Map<String, dynamic>.from(data! as Map);
      if (failPublish) throw StateError('offline');
      publishCalls++;
      schoolVersion = (published!['expectedVersion'] as num).toInt() + 1;
      publishedLabel =
          canonicalLabelAfterPublish ??
          ((published!['stages'] as List).single as Map)['label']?.toString();
      return <String, dynamic>{'version': schoolVersion} as T;
    }
    if (path == '/crm/client-pipelines/rollback') {
      rollbackCalls++;
      schoolVersion++;
      return <String, dynamic>{'version': schoolVersion} as T;
    }
    throw StateError('Unexpected POST $path');
  }
}

Future<void> _open(
  WidgetTester tester,
  _FunnelApi api, {
  String clientType = 'student',
  VoidCallback? onPublished,
  ValueChanged<bool?>? onClosed,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                final result = await showClientPipelineEditor(
                  context,
                  branches: const [],
                  initialClientType: clientType,
                  onPublished: onPublished,
                );
                onClosed?.call(result);
              },
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
  testWidgets('director creates the first pipeline from version zero', (
    tester,
  ) async {
    final api = _FunnelApi(empty: true);
    await _open(tester, api);

    expect(find.textContaining('Воронка ещё не настроена'), findsOneWidget);
    expect(find.text('Версия 0'), findsOneWidget);
    await tester.tap(find.text('Добавить этап'));
    await tester.pumpAndSettle();
    final stage = find.byType(TextFormField).first;
    await tester.enterText(stage, 'Новый клиент');
    await tester.enterText(
      find.byKey(const ValueKey('client-pipeline-reason')),
      'Первая настройка школы',
    );
    final publish = find.byKey(const ValueKey('client-pipeline-publish'));
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Опубликовать').last);
    await tester.pumpAndSettle();

    expect(api.published?['expectedVersion'], 0);
    expect((api.published?['stages'] as List).single['label'], 'Новый клиент');
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor publishes configured labels through the mobile sheet', (
    tester,
  ) async {
    final api = _FunnelApi();
    var publishedCallbacks = 0;
    await _open(
      tester,
      api,
      clientType: 'lead',
      onPublished: () => publishedCallbacks++,
    );

    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('client-pipeline-stage-active')),
      'Постоянное обучение',
    );
    await tester.enterText(
      find.byKey(const ValueKey('client-pipeline-reason')),
      'Уточнили термин',
    );
    final publish = find.byKey(const ValueKey('client-pipeline-publish'));
    await tester.ensureVisible(publish);
    await tester.pumpAndSettle();
    await tester.tap(publish);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(publishedCallbacks, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Опубликовать').last);
    await tester.pumpAndSettle();

    expect(publishedCallbacks, 1);
    expect(api.published?['expectedVersion'], 1);
    expect(api.published?['clientType'], 'lead');
    expect(
      (api.published?['stages'] as List).single['label'],
      'Постоянное обучение',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('publish error keeps the funnel draft intact', (tester) async {
    final api = _FunnelApi(failPublish: true);
    await _open(tester, api);

    final label = find.byKey(const ValueKey('client-pipeline-stage-active'));
    await tester.enterText(label, 'Черновик этапа');
    await tester.enterText(
      find.byKey(const ValueKey('client-pipeline-reason')),
      'Проверка сети',
    );
    final publish = find.byKey(const ValueKey('client-pipeline-publish'));
    await tester.ensureVisible(publish);
    await tester.pumpAndSettle();
    await tester.tap(publish);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Опубликовать').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Не удалось опубликовать'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(label).controller?.text ??
          tester
              .widget<EditableText>(
                find.descendant(of: label, matching: find.byType(EditableText)),
              )
              .controller
              .text,
      'Черновик этапа',
    );
  });

  testWidgets('confirmed type discard clears the reason controller', (
    tester,
  ) async {
    final api = _FunnelApi();
    await _open(tester, api);
    await tester.enterText(
      find.byKey(const ValueKey('client-pipeline-reason')),
      'Черновик текущей воронки',
    );

    await tester.tap(find.byKey(const ValueKey('pipeline-type-student')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Лиды').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Сбросить'));
    await tester.pumpAndSettle();

    final reason = tester.widget<TextField>(
      find.byKey(const ValueKey('client-pipeline-reason')),
    );
    expect(reason.controller!.text, isEmpty);
  });

  testWidgets('type reload remounts a shared stage key with target data', (
    tester,
  ) async {
    final api = _FunnelApi();
    await _open(tester, api);
    final stageKey = const ValueKey('client-pipeline-stage-active');
    expect(
      tester.widget<TextFormField>(find.byKey(stageKey)).controller?.text ??
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(stageKey),
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text,
      'Обучается',
    );

    await tester.tap(find.byKey(const ValueKey('pipeline-type-student')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Лиды').last);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextFormField>(find.byKey(stageKey)).controller?.text ??
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(stageKey),
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text,
      'Новый лид',
    );
  });

  testWidgets('same-scope publish remounts stage fields at canonical version', (
    tester,
  ) async {
    final api = _FunnelApi(
      canonicalLabelAfterPublish: 'Канонический этап версии 2',
    );
    await _open(tester, api);
    final stageKey = const ValueKey('client-pipeline-stage-active');
    await tester.enterText(find.byKey(stageKey), 'Локальный черновик');
    await tester.enterText(
      find.byKey(const ValueKey('client-pipeline-reason')),
      'Проверка canonical reload',
    );

    final publish = find.byKey(const ValueKey('client-pipeline-publish'));
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Опубликовать').last);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextFormField>(find.byKey(stageKey)).controller?.text ??
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(stageKey),
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text,
      'Канонический этап версии 2',
    );
  });

  testWidgets('publish reload failure keeps close result true', (tester) async {
    final api = _FunnelApi(failReloadAfterMutation: true);
    bool? closeResult;
    await _open(tester, api, onClosed: (result) => closeResult = result);
    await tester.enterText(
      find.byKey(const ValueKey('client-pipeline-reason')),
      'Терминальная публикация',
    );

    final publish = find.byKey(const ValueKey('client-pipeline-publish'));
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Опубликовать').last);
    await tester.pumpAndSettle();

    expect(api.publishCalls, 1);
    expect(find.text('Не удалось загрузить воронку.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Закрыть'));
    await tester.pumpAndSettle();
    expect(closeResult, isTrue);
    expect(api.publishCalls, 1);
  });

  testWidgets('rollback reload failure keeps close result true', (
    tester,
  ) async {
    final api = _FunnelApi(failReloadAfterMutation: true, withHistory: true);
    bool? closeResult;
    await _open(tester, api, onClosed: (result) => closeResult = result);

    final rollback = find.widgetWithText(TextButton, 'Вернуть');
    await tester.ensureVisible(rollback);
    await tester.tap(rollback);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Вернуть'));
    await tester.pumpAndSettle();

    expect(api.rollbackCalls, 1);
    expect(find.text('Не удалось загрузить воронку.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Закрыть'));
    await tester.pumpAndSettle();
    expect(closeResult, isTrue);
    expect(api.rollbackCalls, 1);
  });
}
