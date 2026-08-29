import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/models/client_internal_context.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_internal_context_widgets.dart';

import 'card_fake_api.dart';

void main() {
  testWidgets('restored internal note resumes debounce with base version', (
    tester,
  ) async {
    final saves = <ClientInternalNoteDraft>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientInternalNoteCard(
            loading: false,
            note: const ClientInternalNote(body: 'Сервер', version: 6),
            initialDraft: const ClientInternalNoteDraft(
              body: 'Локальный текст',
              expectedVersion: 5,
            ),
            onSave: (body, expectedVersion) async {
              saves.add(
                ClientInternalNoteDraft(
                  body: body,
                  expectedVersion: expectedVersion,
                ),
              );
              return const ClientInternalNote(
                body: 'Локальный текст',
                version: 6,
              );
            },
            onReload: () async =>
                const ClientInternalNote(body: 'Сервер', version: 6),
            onRetry: () {},
            onPendingChanged: (_) {},
            onFlushChanged: (_) {},
            onDraftChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 799));
    expect(saves, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(saves, hasLength(1));
    expect(saves.single.body, 'Локальный текст');
    expect(saves.single.expectedVersion, 5);
  });

  testWidgets('hard unmount keeps the latest pre-debounce client draft', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(
      role: 'manager',
      lead: const {
        'id': 'lead-1',
        'version': 4,
        'firstName': 'Иван',
        'lastName': 'Петров',
        'phone': '+79990000000',
        'customData': <String, dynamic>{},
      },
    );
    final workspace = _workspace();
    addTearDown(workspace.dispose);
    final tabId = workspace.state.activeTabId;
    late StateSetter updateHost;
    var cardMounted = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          crmRealtimeProvider.overrideWith(
            (ref) => const Stream<CrmChangedEvent>.empty(),
          ),
        ],
        child: MaterialApp(
          home: WorkspaceNavigationScope(
            controller: workspace,
            isDesktop: true,
            child: StatefulBuilder(
              builder: (context, setState) {
                updateHost = setState;
                return cardMounted
                    ? Material(
                        child: ClientCard(
                          lead: const {'id': 'lead-1'},
                          entityType: 'lead',
                          routed: true,
                          workspaceTabId: tabId,
                          capabilitySnapshot: _snapshot,
                        ),
                      )
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Имя'),
      'До закрытия',
    );
    await tester.pump();

    const formKey = 'client-card:lead:lead-1';
    final beforeClose = workspace.state.activeTab.forms[formKey];
    expect(beforeClose?.dirty, isTrue);
    expect(
      (((beforeClose?.draft['lead'] as Map)['core'] as Map)['firstName']),
      'До закрытия',
    );
    expect(beforeClose?.expectedVersion, 4);
    expect(api.updateLeadBodies, isEmpty);

    updateHost(() => cardMounted = false);
    await tester.pump();

    expect(workspace.state.activeTab.forms[formKey]?.dirty, isTrue);
    expect(
      (((workspace.state.activeTab.forms[formKey]?.draft['lead'] as Map)['core']
          as Map)['firstName']),
      'До закрытия',
    );
    expect(api.updateLeadBodies, isEmpty);
  });

  testWidgets('restored client-card draft rebases and resumes autosave', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(
      role: 'manager',
      lead: const {
        'id': 'lead-1',
        'version': 4,
        'firstName': 'Иван',
        'lastName': 'Петров',
        'phone': '+79990000000',
        'customData': <String, dynamic>{},
      },
    );
    final workspace = _workspace();
    addTearDown(workspace.dispose);
    final tabId = workspace.state.activeTabId;
    const formKey = 'client-card:lead:lead-1';
    workspace.registerForm(
      tabId,
      formKey,
      expectedVersion: 4,
      draft: const {
        'schemaVersion': 1,
        'entityType': 'lead',
        'entityId': 'lead-1',
        'lead': {
          'expectedVersion': 4,
          'core': {'firstName': 'Восстановленный'},
          'custom': <String, Object?>{},
        },
      },
    );
    workspace.updateForm(tabId, formKey, dirty: true, expectedVersion: 4);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          crmRealtimeProvider.overrideWith(
            (ref) => const Stream<CrmChangedEvent>.empty(),
          ),
        ],
        child: MaterialApp(
          home: WorkspaceNavigationScope(
            controller: workspace,
            isDesktop: true,
            child: Material(
              child: ClientCard(
                lead: const {'id': 'lead-1'},
                entityType: 'lead',
                routed: true,
                workspaceTabId: tabId,
                capabilitySnapshot: _snapshot,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(api.updateLeadBodies, hasLength(1));
    expect(api.updateLeadBodies.single['expectedVersion'], 4);
    expect(api.updateLeadBodies.single['firstName'], 'Восстановленный');
    expect(workspace.state.activeTab.forms[formKey]?.dirty, isFalse);
  });
}

const _snapshot = CapabilitySnapshot(
  accountId: 'account-1',
  role: 'manager',
  accessVersion: 1,
  capabilities: {'crm.client.read.basic'},
  scopes: {},
);

WorkspaceController _workspace() => WorkspaceController(
  accountId: 'account-1',
  initialLink: EntityLink.typed(
    entityType: EntityLinkType.client,
    entityId: 'lead-1',
    variant: 'lead',
  ),
  sharedScope: WorkspaceSharedScope(
    session: Object(),
    cache: Object(),
    realtime: Object(),
  ),
  titleResolver: (_) => 'Клиент',
);
