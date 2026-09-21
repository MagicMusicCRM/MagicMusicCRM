import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/notification_delivery_journal_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

class _DeliveryApi extends MagicApiClient {
  _DeliveryApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final queries = <Map<String, dynamic>>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/admin/notifications/deliveries') {
      queries.add(Map<String, dynamic>.from(queryParameters ?? {}));
      return <String, dynamic>{
            'total': 1,
            'items': [
              {
                'notificationId': 'notification-1',
                'title': 'Новая задача',
                'entityType': 'task',
                'entityId': 'task-1',
                'recipientName': 'Анна Менеджер',
                'recipientEntityType': 'staff',
                'recipientEntityId': 'staff-1',
                'branchName': 'Центр',
                'channel': 'push',
                'provider': 'firebase',
                'status': 'sent',
                'attemptCount': 1,
                'updatedAt': '2026-09-20T10:01:00.000Z',
              },
            ],
          }
          as T;
    }
    return <String, dynamic>{} as T;
  }
}

void main() {
  testWidgets('delivery journal exposes filters and both workflow links', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _DeliveryApi();
    final opened = <EntityLink>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(
            body: NotificationDeliveryJournalPanel(
              filter: DashboardFilter(
                from: DateTime(2026, 9, 1),
                to: DateTime(2026, 9, 30),
                branchId: 'branch-1',
              ),
              onOpenEntity: opened.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('delivery-journal-channel')), findsOneWidget);
    expect(find.byKey(const Key('delivery-journal-status')), findsOneWidget);
    expect(find.text('Новая задача'), findsOneWidget);
    expect(find.textContaining('Анна Менеджер'), findsOneWidget);
    expect(find.textContaining('Доставлено'), findsOneWidget);
    expect(api.queries.single['branchId'], 'branch-1');

    await tester.tap(find.byTooltip('Открыть связанную запись'));
    await tester.pump();
    await tester.tap(find.byTooltip('Открыть карточку получателя'));
    await tester.pump();

    expect(opened.map((link) => link.rawEntityType), ['task', 'staff']);
  });
}
