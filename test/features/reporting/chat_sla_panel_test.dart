import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/chat_sla_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

class _ChatSlaApi extends MagicApiClient {
  _ChatSlaApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final queries = <Map<String, dynamic>>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/analytics/chats/sla') {
      queries.add(Map<String, dynamic>.from(queryParameters ?? {}));
      return <String, dynamic>{
            'inboundCount': 10,
            'respondedCount': 8,
            'responseRate': 0.8,
            'avgMinutes': 12.5,
            'medianMinutes': 9,
            'p90Minutes': 30,
            'slowChats': [
              {
                'chatId': 'chat-1',
                'clientName': 'Анна Клиент',
                'inboundAt': '2026-09-20T10:00:00.000Z',
                'responseAt': '2026-09-20T10:42:00.000Z',
                'minutes': 42,
              },
            ],
          }
          as T;
    }
    return <String, dynamic>{} as T;
  }
}

void main() {
  testWidgets('chat SLA explains the formula, respects branch and opens chat', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _ChatSlaApi();
    EntityLink? opened;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(
            body: ChatSlaPanel(
              filter: DashboardFilter(
                from: DateTime(2026, 9, 1),
                to: DateTime(2026, 9, 30),
                branchId: 'branch-1',
              ),
              onOpenEntity: (link) => opened = link,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('Одно обращение начинается'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('13 мин'), findsOneWidget);
    expect(find.text('Анна Клиент'), findsOneWidget);
    expect(api.queries.single['branchId'], 'branch-1');

    await tester.tap(find.text('Анна Клиент'));
    expect(opened?.rawEntityType, 'chat');
    expect(opened?.entityId, 'chat-1');
  });
}
