import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/notification_bell_widget.dart';
import 'package:magic_music_crm/core/widgets/v7/adaptive_surface.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/shared_tasks_v4_panel.dart';

import 'evidence_screenshot.dart';
import '../test/features/v4/shared_tasks_ui_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('task audience preview is usable on Android and Windows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    await tester.ensureVisible(find.text('Напомнить в приложении'));
    await tester.tap(find.text('Напомнить в приложении'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shared-task-reminder-at')), findsOneWidget);
    await captureEvidence(tester, 'task-all-day-reminder');

    await tester.ensureVisible(find.text('На весь день'));
    await tester.tap(find.text('На весь день'));
    await tester.pumpAndSettle();
    expect(find.text('Окончание'), findsOneWidget);
    expect(find.byKey(const Key('shared-task-reminder-at')), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pumpAndSettle();
    await captureEvidence(tester, 'task-interval-reminder');
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

  testWidgets('task notification opens the exact task', (tester) async {
    await initializeDateFormatting('ru');
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const taskId = '11111111-1111-4111-8111-111111111111';
    const snapshot = CapabilitySnapshot(
      accountId: 'manager-1',
      role: 'manager',
      accessVersion: 1,
      capabilities: {'workflow.task.read'},
      scopes: {},
    );
    final notifications = _TaskReminderNotifications(taskId);
    final workspace = WorkspaceController(
      accountId: 'manager-1',
      initialLink: EntityLink.typed(
        entityType: EntityLinkType.chat,
        entityId: 'home',
      ),
      titleResolver: const EntityPresentationResolver().pageTitle,
      sharedScope: WorkspaceSharedScope(
        session: Object(),
        cache: Object(),
        realtime: Object(),
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: ProviderScope(
          overrides: [
            magicNotificationsServiceProvider.overrideWithValue(notifications),
            capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: WorkspaceNavigationScope(
                controller: workspace,
                isDesktop: true,
                child: const Center(child: NotificationBellWidget()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Уведомления'));
    await tester.pumpAndSettle();
    expect(find.text('Напоминание о задаче'), findsOneWidget);
    expect(
      find.text('Открытая общая задача ожидает действия.'),
      findsOneWidget,
    );
    await captureEvidence(tester, 'task-reminder-notification');
    await tester.tap(find.text('Открытая общая задача ожидает действия.'));
    await tester.pumpAndSettle();

    expect(notifications.marked, ['task-reminder-notification']);
    expect(workspace.state.activeTab.currentRoute.link.rawEntityType, 'task');
    expect(workspace.state.activeTab.currentRoute.link.entityId, taskId);
    debugPrint('V7_TASK_REMINDER_ROUTE_DEVICE_PASS');
  });

  testWidgets('lesson change notification opens the exact lesson', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const lessonId = '22222222-2222-4222-8222-222222222222';
    const snapshot = CapabilitySnapshot(
      accountId: 'teacher-1',
      role: 'teacher',
      accessVersion: 1,
      capabilities: {'schedule.lesson.read.assigned'},
      scopes: {},
    );
    final notifications = _LessonChangeNotifications(lessonId);
    final workspace = WorkspaceController(
      accountId: 'teacher-1',
      initialLink: EntityLink.typed(
        entityType: EntityLinkType.chat,
        entityId: 'home',
      ),
      titleResolver: const EntityPresentationResolver().pageTitle,
      sharedScope: WorkspaceSharedScope(
        session: Object(),
        cache: Object(),
        realtime: Object(),
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: ProviderScope(
          overrides: [
            magicNotificationsServiceProvider.overrideWithValue(notifications),
            capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: WorkspaceNavigationScope(
                controller: workspace,
                isDesktop: true,
                child: const Center(child: NotificationBellWidget()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Уведомления'));
    await tester.pumpAndSettle();
    expect(find.text('Занятие перенесено'), findsOneWidget);
    expect(
      find.text('Новая дата и время занятия: 14.08.2026 12:00.'),
      findsOneWidget,
    );
    await captureEvidence(tester, 'lesson-change-notification');
    await tester.tap(
      find.text('Новая дата и время занятия: 14.08.2026 12:00.'),
    );
    await tester.pumpAndSettle();

    expect(notifications.marked, ['lesson-change-notification']);
    expect(workspace.state.activeTab.currentRoute.link.rawEntityType, 'lesson');
    expect(workspace.state.activeTab.currentRoute.link.entityId, lessonId);
    debugPrint('V7_LESSON_CHANGE_NOTIFICATION_DEVICE_PASS');
  });
}

class _TaskReminderNotifications implements MagicNotificationsService {
  _TaskReminderNotifications(this.taskId);

  final String taskId;
  final List<String> marked = [];

  @override
  Future<List<Map<String, dynamic>>> list({
    bool? unread,
    int limit = 50,
    String? cursor,
  }) async => [
    {
      'id': 'task-reminder-notification',
      'type': 'system',
      'title': 'Напоминание о задаче',
      'body': 'Открытая общая задача ожидает действия.',
      'data': {'entityType': 'task', 'entityId': taskId},
      'is_read': false,
      'created_at': '2026-08-12T08:00:00.000Z',
    },
  ];

  @override
  Future<Map<String, dynamic>> markRead(String id) async {
    marked.add(id);
    return {'id': id, 'is_read': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _LessonChangeNotifications implements MagicNotificationsService {
  _LessonChangeNotifications(this.lessonId);

  final String lessonId;
  final List<String> marked = [];

  @override
  Future<List<Map<String, dynamic>>> list({
    bool? unread,
    int limit = 50,
    String? cursor,
  }) async => [
    {
      'id': 'lesson-change-notification',
      'type': 'lesson_change',
      'title': 'Занятие перенесено',
      'body': 'Новая дата и время занятия: 14.08.2026 12:00.',
      'data': {
        'entityType': 'lesson',
        'entityId': lessonId,
        'eventType': 'rescheduled',
      },
      'is_read': false,
      'created_at': '2026-08-12T09:00:00.000Z',
    },
  ];

  @override
  Future<Map<String, dynamic>> markRead(String id) async {
    marked.add(id);
    return {'id': id, 'is_read': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
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
