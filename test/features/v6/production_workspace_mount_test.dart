import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_host.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';

void main() {
  const snapshot = CapabilitySnapshot(
    accountId: 'account-1',
    role: 'manager',
    accessVersion: 1,
    capabilities: {'crm.client.read.basic'},
    scopes: {},
  );

  testWidgets(
    'desktop production host mounts existing workspace with 10 tabs',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.reset);
      final backend = InMemoryWorkspaceKeyValueStore();
      final store = AccountWorkspaceStore(backend);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [accountWorkspaceStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1200, 800)),
              child: Scaffold(
                body: ProductionWorkspaceHost(
                  snapshot: snapshot,
                  tabBuilder: (_, tab) =>
                      Text('${tab.tabId}:${tab.currentRoute.link.entityId}'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final shell = tester.widget<DesktopWorkspaceShell>(
        find.byType(DesktopWorkspaceShell),
      );
      for (var index = 1; index < 10; index++) {
        shell.controller.open(
          EntityLink.typed(
            entityType: EntityLinkType.client,
            entityId: 'client-$index',
            variant: 'student',
          ),
          explicitNew: true,
        );
      }
      await tester.pump();

      expect(shell.controller.state.tabs, hasLength(10));
      expect(find.text('tab-10:client-9'), findsOneWidget);
    },
  );

  testWidgets('compact host keeps one mobile route stack without tab strip', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountWorkspaceStoreProvider.overrideWithValue(
            AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
          ),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(600, 800)),
            child: Scaffold(
              body: ProductionWorkspaceHost(
                snapshot: snapshot,
                tabBuilder: (_, tab) => Text(tab.currentRoute.link.entityId),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DesktopWorkspaceShell), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
