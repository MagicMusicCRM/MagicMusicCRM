import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';
import 'package:magic_music_crm/core/widgets/notification_bell_widget.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';

class _FakeNotifications implements MagicNotificationsService {
  _FakeNotifications({List<Map<String, dynamic>>? items})
    : _items =
          items ??
          [
            {
              'id': 'notification-1',
              'type': 'new_lead',
              'title': 'Новая заявка',
              'body': 'Заявка UAT-044 Внешняя — источник: Звонок',
              'data': {
                'entityType': 'lead',
                'entityId': 'lead-1',
                'entityName': 'Заявка UAT-044 Внешняя',
              },
              'is_read': false,
            },
          ];

  final List<Map<String, dynamic>> _items;
  final marked = <String>[];

  @override
  Future<List<Map<String, dynamic>>> list({
    bool? unread,
    int limit = 50,
    String? cursor,
  }) async => _items.map(Map<String, dynamic>.from).toList();

  @override
  Future<Map<String, dynamic>> markRead(String id) async {
    marked.add(id);
    final index = _items.indexWhere((item) => item['id'] == id);
    if (index >= 0) _items[index] = {..._items[index], 'is_read': true};
    return {'id': id, 'is_read': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  testWidgets('notification text opens its linked Lead in a desktop tab', (
    tester,
  ) async {
    const snapshot = CapabilitySnapshot(
      accountId: 'director-1',
      role: 'director',
      accessVersion: 1,
      capabilities: {'crm.client.read.basic'},
      scopes: {},
    );
    final notifications = _FakeNotifications();
    final workspace = WorkspaceController(
      accountId: 'director-1',
      initialLink: EntityLink.typed(
        entityType: EntityLinkType.chat,
        entityId: 'home',
      ),
      sharedScope: WorkspaceSharedScope(
        session: Object(),
        cache: Object(),
        realtime: Object(),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicNotificationsServiceProvider.overrideWithValue(notifications),
          capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WorkspaceNavigationScope(
              controller: workspace,
              isDesktop: true,
              child: const NotificationBellWidget(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Уведомления'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Заявка UAT-044 Внешняя — источник: Звонок'));
    await tester.pumpAndSettle();

    expect(notifications.marked, ['notification-1']);
    expect(workspace.state.tabs, hasLength(2));
    expect(workspace.state.activeTab.currentRoute.link.rawEntityType, 'lead');
    expect(workspace.state.activeTab.currentRoute.link.entityId, 'lead-1');
    expect(workspace.state.activeTab.titleHint, 'Лид · Заявка UAT-044 Внешняя');
  });

  testWidgets(
    'task reminder opens the exact task and keeps server read state',
    (tester) async {
      const snapshot = CapabilitySnapshot(
        accountId: 'manager-1',
        role: 'manager',
        accessVersion: 1,
        capabilities: {'workflow.task.read'},
        scopes: {},
      );
      final notifications = _FakeNotifications(
        items: [
          {
            'id': 'notification-task',
            'type': 'system',
            'title': 'Напоминание о задаче',
            'body': 'Открытая общая задача ожидает действия.',
            'data': {
              'entityType': 'task',
              'entityId': '11111111-1111-4111-8111-111111111111',
            },
            'is_read': false,
          },
        ],
      );
      final workspace = WorkspaceController(
        accountId: 'manager-1',
        initialLink: EntityLink.typed(
          entityType: EntityLinkType.chat,
          entityId: 'home',
        ),
        sharedScope: WorkspaceSharedScope(
          session: Object(),
          cache: Object(),
          realtime: Object(),
        ),
      );

      Future<void> pumpBell(Key key) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            magicNotificationsServiceProvider.overrideWithValue(notifications),
            capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: WorkspaceNavigationScope(
                controller: workspace,
                isDesktop: true,
                child: NotificationBellWidget(key: key),
              ),
            ),
          ),
        ),
      );

      await pumpBell(const ValueKey('first-session'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Уведомления'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Открытая общая задача ожидает действия.'));
      await tester.pumpAndSettle();

      expect(notifications.marked, ['notification-task']);
      expect(workspace.state.activeTab.currentRoute.link.rawEntityType, 'task');
      expect(
        workspace.state.activeTab.currentRoute.link.entityId,
        '11111111-1111-4111-8111-111111111111',
      );

      await pumpBell(const ValueKey('restarted-session'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Уведомления'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Открытая общая задача ожидает действия.'));
      await tester.pumpAndSettle();
      expect(notifications.marked, ['notification-task']);
    },
  );

  testWidgets('lesson change opens the exact lesson', (tester) async {
    const lessonId = '22222222-2222-4222-8222-222222222222';
    const snapshot = CapabilitySnapshot(
      accountId: 'teacher-1',
      role: 'teacher',
      accessVersion: 1,
      capabilities: {'schedule.lesson.read.assigned'},
      scopes: {},
    );
    final notifications = _FakeNotifications(
      items: [
        {
          'id': 'notification-lesson',
          'type': 'lesson_change',
          'title': 'Занятие перенесено',
          'body': 'Новая дата и время занятия: 14.08.2026 12:00.',
          'data': {
            'entityType': 'lesson',
            'entityId': lessonId,
            'eventType': 'rescheduled',
          },
          'is_read': false,
        },
      ],
    );
    final workspace = WorkspaceController(
      accountId: 'teacher-1',
      initialLink: EntityLink.typed(
        entityType: EntityLinkType.chat,
        entityId: 'home',
      ),
      sharedScope: WorkspaceSharedScope(
        session: Object(),
        cache: Object(),
        realtime: Object(),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicNotificationsServiceProvider.overrideWithValue(notifications),
          capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WorkspaceNavigationScope(
              controller: workspace,
              isDesktop: true,
              child: const NotificationBellWidget(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Уведомления'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Новая дата и время занятия: 14.08.2026 12:00.'),
    );
    await tester.pumpAndSettle();

    expect(notifications.marked, ['notification-lesson']);
    expect(workspace.state.activeTab.currentRoute.link.rawEntityType, 'lesson');
    expect(workspace.state.activeTab.currentRoute.link.entityId, lessonId);
  });
}
