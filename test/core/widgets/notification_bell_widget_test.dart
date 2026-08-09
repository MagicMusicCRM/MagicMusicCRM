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
  final marked = <String>[];

  @override
  Future<List<Map<String, dynamic>>> list({
    bool? unread,
    int limit = 50,
    String? cursor,
  }) async => [
    {
      'id': 'notification-1',
      'type': 'new_lead',
      'title': 'Новая заявка',
      'body': 'Заявка UAT-044 Внешняя — источник: Звонок',
      'data': {'entityType': 'lead', 'entityId': 'lead-1'},
          'is_read': false,
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
  });
}
