import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/student_funnel_editor.dart';

class _FunnelApi extends MagicApiClient {
  _FunnelApi({this.failPublish = false})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool failPublish;
  Map<String, dynamic>? published;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/student-funnel') {
      return <String, dynamic>{
            'branchId': queryParameters?['branchId'],
            'source': 'school',
            'schoolVersion': 1,
            'branchVersion': 0,
            'stages': [
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
    if (path == '/crm/student-funnel/revisions') {
      return <String, dynamic>{
            'items': [
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
    if (path == '/crm/student-funnel/publish') {
      published = Map<String, dynamic>.from(data! as Map);
      if (failPublish) throw StateError('offline');
      return <String, dynamic>{'version': 2} as T;
    }
    throw StateError('Unexpected POST $path');
  }
}

Future<void> _open(WidgetTester tester, _FunnelApi api) async {
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
              onPressed: () =>
                  showStudentFunnelEditor(context, branches: const []),
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
  testWidgets('editor publishes configured labels through the mobile sheet', (
    tester,
  ) async {
    final api = _FunnelApi();
    await _open(tester, api);

    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('student-funnel-stage-active')),
      'Постоянное обучение',
    );
    await tester.enterText(
      find.byKey(const ValueKey('student-funnel-reason')),
      'Уточнили термин',
    );
    final publish = find.byKey(const ValueKey('student-funnel-publish'));
    await tester.ensureVisible(publish);
    await tester.pumpAndSettle();
    await tester.tap(publish);
    await tester.pumpAndSettle();

    expect(api.published?['expectedVersion'], 1);
    expect(
      (api.published?['stages'] as List).single['label'],
      'Постоянное обучение',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('publish error keeps the funnel draft intact', (tester) async {
    final api = _FunnelApi(failPublish: true);
    await _open(tester, api);

    final label = find.byKey(const ValueKey('student-funnel-stage-active'));
    await tester.enterText(label, 'Черновик этапа');
    await tester.enterText(
      find.byKey(const ValueKey('student-funnel-reason')),
      'Проверка сети',
    );
    final publish = find.byKey(const ValueKey('student-funnel-publish'));
    await tester.ensureVisible(publish);
    await tester.pumpAndSettle();
    await tester.tap(publish);
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
