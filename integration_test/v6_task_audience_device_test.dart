import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/v7/adaptive_surface.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/shared_tasks_v4_panel.dart';

import 'evidence_screenshot.dart';
import '../test/features/v4/shared_tasks_ui_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('task audience preview is usable on Android and Windows', (
    tester,
  ) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const _TaskAudienceDeviceHome(),
        ),
      ),
    );

    await tester.tap(find.text('Новая задача'));
    await tester.pumpAndSettle();
    expect(find.text('Сейчас получат: 4'), findsOneWidget);
    expect(
      find.textContaining('Вся школа — динамический состав'),
      findsOneWidget,
    );
    if (find
        .byKey(const ValueKey('magic-sheet-mobile'))
        .evaluate()
        .isNotEmpty) {
      await tester.tap(find.text('Развернуть'));
      await tester.pumpAndSettle();
      expect(find.text('Свернуть'), findsOneWidget);
    }
    await captureEvidence(tester, 'task-audience-preview');

    await tester.ensureVisible(find.byKey(const Key('shared-task-title')));
    await tester.enterText(
      find.byKey(const Key('shared-task-title')),
      'Проверка адресатов',
    );
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Создать'));
    await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pumpAndSettle();

    expect(find.text('Сохранено: Вся школа'), findsOneWidget);
    debugPrint('V6_TASK_AUDIENCE_DEVICE_PASS');
  });

  testWidgets('overdue reminder stays visible until explicit close', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = FakeSharedTasksDataSource();
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: SharedTasksV4Panel(dataSource: source, canWrite: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Просроченных задач: 1'), findsOneWidget);
    expect(find.text('Закрыть задачу'), findsOneWidget);
    await captureEvidence(tester, 'task-overdue-explicit-close');
    await tester.tap(find.text('Закрыть задачу'));
    await tester.pumpAndSettle();
    expect(find.text('Нет задач'), findsOneWidget);
  });
}

class _TaskAudienceDeviceHome extends StatefulWidget {
  const _TaskAudienceDeviceHome();

  @override
  State<_TaskAudienceDeviceHome> createState() =>
      _TaskAudienceDeviceHomeState();
}

class _TaskAudienceDeviceHomeState extends State<_TaskAudienceDeviceHome> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _saved
            ? const Text('Сохранено: Вся школа')
            : FilledButton(
                onPressed: () async {
                  final result =
                      await showMagicAdaptiveSurface<Map<String, dynamic>>(
                        context,
                        kind: AppSurfaceKind.selection,
                        title: 'Новая задача',
                        builder: (_) => SharedTaskEditor(
                          embedded: true,
                          audienceOptions: const [],
                          audiencePreview: (audiences) async => {
                            'totalRecipients': 4,
                            'hasDynamicMembership': true,
                            'selectors': const [
                              {
                                'type': 'allBranches',
                                'label': 'Вся школа',
                                'mode': 'dynamic',
                                'currentRecipientCount': 4,
                              },
                            ],
                          },
                        ),
                      );
                  if (mounted && result != null) setState(() => _saved = true);
                },
                child: const Text('Новая задача'),
              ),
      ),
    );
  }
}
