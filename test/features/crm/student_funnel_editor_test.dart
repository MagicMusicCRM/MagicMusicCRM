import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/student_funnel_editor.dart';

class _FunnelApi extends MagicApiClient {
  _FunnelApi({this.failPublish = false, this.empty = false})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool failPublish;
  final bool empty;
  Map<String, dynamic>? published;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/client-pipelines') {
      return <String, dynamic>{
            'clientType': queryParameters?['clientType'],
            'branchId': queryParameters?['branchId'],
            'source': 'school',
            'schoolVersion': empty ? 0 : 1,
            'branchVersion': 0,
            'stages': empty
                ? const <Map<String, dynamic>>[]
                : [
                    {
                      'key': 'active',
                      'label': 'Обучается',
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
                : [
                    {'version': 1, 'reason': 'Системная версия'},
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
      return <String, dynamic>{'version': 2} as T;
    }
    throw StateError('Unexpected POST $path');
  }
}

Future<void> _open(
  WidgetTester tester,
  _FunnelApi api, {
  String clientType = 'student',
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
              onPressed: () => showClientPipelineEditor(
                context,
                branches: const [],
                initialClientType: clientType,
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
    await _open(tester, api, clientType: 'lead');

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
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Опубликовать').last);
    await tester.pumpAndSettle();

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
}
