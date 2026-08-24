import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/workspace/entity_navigation_scope.dart';

void main() {
  const snapshot = CapabilitySnapshot(
    accountId: 'account-1',
    role: 'director',
    accessVersion: 1,
    capabilities: {'crm.client.read.basic', 'crm.client.write'},
    scopes: {},
  );

  testWidgets(
    'desktop entity navigation uses the lightweight port without a workspace controller',
    (tester) async {
      final navigationKey = GlobalKey();
      EntityLink? openedLink;
      ContextViewState? preservedView;
      String? openedTitle;
      final link = EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: 'student-1',
        variant: 'student',
        presentation: const EntityPresentationReference(primary: 'Иванов Иван'),
      );
      final sourceView = ContextViewState(
        filters: const {'branch': 'branch-1'},
        scrollOffset: 84,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntityNavigationScope(
              isDesktop: true,
              preserveCurrentView: (view) => preservedView = view,
              open: (entityLink, {titleHint}) {
                openedLink = entityLink;
                openedTitle = titleHint;
                return EntityNavigationOpenResult.opened;
              },
              child: SizedBox(key: navigationKey),
            ),
          ),
        ),
      );

      final resolution = await navigateEntityLink(
        navigationKey.currentContext!,
        snapshot,
        link,
        sourceViewState: sourceView,
      );

      expect(resolution.canOpen, isTrue);
      expect(openedLink, same(link));
      expect(openedTitle, 'Ученик · Иванов Иван');
      expect(preservedView, same(sourceView));
    },
  );

  testWidgets('desktop entity navigation reports the workspace tab limit', (
    tester,
  ) async {
    final navigationKey = GlobalKey();
    final link = EntityLink.typed(
      entityType: EntityLinkType.client,
      entityId: 'student-2',
      variant: 'student',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntityNavigationScope(
            isDesktop: true,
            preserveCurrentView: (_) {},
            open: (_, {titleHint}) => EntityNavigationOpenResult.limitReached,
            child: SizedBox(key: navigationKey),
          ),
        ),
      ),
    );

    await navigateEntityLink(navigationKey.currentContext!, snapshot, link);
    await tester.pump();

    expect(find.text('Можно открыть не больше 10 вкладок.'), findsOneWidget);
  });
}
