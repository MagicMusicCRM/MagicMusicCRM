import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/workspace/shared_entity_cache.dart';
import 'package:magic_music_crm/core/workspace/workspace_conflict_banner.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';

void main() {
  final client = EntityLink.typed(
    entityType: EntityLinkType.client,
    entityId: 'client-1',
  );

  WorkspaceController controller() => WorkspaceController(
    accountId: 'account-1',
    initialLink: EntityLink.typed(
      entityType: EntityLinkType.report,
      entityId: 'home',
    ),
    sharedScope: WorkspaceSharedScope(
      session: Object(),
      cache: Object(),
      realtime: Object(),
    ),
  );

  test('cache separates projection and version identities', () {
    final cache = SharedEntityCache();
    cache.put(
      link: client,
      projectionScope: 'teacher-limited',
      version: 4,
      value: const {'name': 'Иван'},
    );
    cache.put(
      link: client,
      projectionScope: 'director-full',
      version: 5,
      value: const {'name': 'Иван', 'balance': 1000},
    );

    expect(
      cache
          .latest<Map<String, Object?>>(
            client,
            projectionScope: 'teacher-limited',
          )
          ?.key
          .version,
      4,
    );
    expect(
      cache
          .latest<Map<String, Object?>>(
            client,
            projectionScope: 'director-full',
          )
          ?.key
          .version,
      5,
    );
  });

  test(
    'clean tab refetches once for duplicate event within two seconds',
    () async {
      final workspace = controller();
      final tabId = workspace.open(client);
      final refetches = <String>[];
      final coordinator = WorkspaceInvalidationCoordinator(
        workspace: workspace,
        cache: SharedEntityCache(),
        refetch: (tab, _, version) async => refetches.add('$tab:$version'),
      );
      const event = EntityInvalidationEvent(
        eventId: 'event-1',
        link: EntityLink(
          entityType: EntityLinkType.client,
          entityId: 'client-1',
          rawEntityType: 'client',
        ),
        version: 6,
      );

      final stopwatch = Stopwatch()..start();
      expect(await coordinator.handle(event), isTrue);
      expect(await coordinator.handle(event), isFalse);
      stopwatch.stop();

      expect(refetches, ['$tabId:6']);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  test(
    'dirty tab preserves draft and becomes conflicted without refetch',
    () async {
      final workspace = controller();
      final first = workspace.open(client);
      final dirty = workspace.open(client, explicitNew: true);
      workspace.registerForm(
        dirty,
        'client-form',
        expectedVersion: 5,
        draft: const {'name': 'Несохранённое имя'},
      );
      workspace.updateForm(dirty, 'client-form', dirty: true);
      final refetched = <String>[];
      final coordinator = WorkspaceInvalidationCoordinator(
        workspace: workspace,
        cache: SharedEntityCache(),
        refetch: (tabId, link, version) async => refetched.add(tabId),
      );

      await coordinator.handle(
        EntityInvalidationEvent(eventId: 'event-2', link: client, version: 6),
      );

      expect(refetched, [first]);
      final form = workspace.state.tabs
          .firstWhere((tab) => tab.tabId == dirty)
          .forms['client-form']!;
      expect(form.draft['name'], 'Несохранённое имя');
      expect(form.conflict?.serverVersion, 6);
      expect(form.conflict?.source, 'realtime');
    },
  );

  testWidgets('409 exposes reload, merge and cancel conflict flow', (
    tester,
  ) async {
    final workspace = controller();
    final tabId = workspace.open(client);
    workspace.registerForm(
      tabId,
      'client-form',
      expectedVersion: 5,
      draft: const {'name': 'Локальное имя'},
    );
    workspace.updateForm(tabId, 'client-form', dirty: true);
    final coordinator = WorkspaceInvalidationCoordinator(
      workspace: workspace,
      cache: SharedEntityCache(),
      refetch: (tabId, link, version) async {},
    );
    expect(
      coordinator.handleWriteError(
        tabId: tabId,
        formKey: 'client-form',
        error: const MagicApiException(
          statusCode: 409,
          message: 'stale',
          details: {'currentVersion': 7},
        ),
      ),
      isTrue,
    );

    var action = '';
    final form = workspace.state.tabs
        .firstWhere((tab) => tab.tabId == tabId)
        .forms['client-form']!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceConflictBanner(
            form: form,
            onReload: () => action = 'reload',
            onMerge: () => action = 'merge',
            onCancel: () => action = 'cancel',
          ),
        ),
      ),
    );

    expect(find.textContaining('Ваш ввод сохранён'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('workspace-conflict-reload-client-form')),
    );
    expect(action, 'reload');
    await tester.tap(
      find.byKey(const ValueKey('workspace-conflict-merge-client-form')),
    );
    expect(action, 'merge');
    await tester.tap(
      find.byKey(const ValueKey('workspace-conflict-cancel-client-form')),
    );
    expect(action, 'cancel');

    workspace.mergeConflictedForm(
      tabId,
      'client-form',
      serverVersion: 7,
      mergedDraft: const {'name': 'Merged'},
    );
    final merged = workspace.state.tabs
        .firstWhere((tab) => tab.tabId == tabId)
        .forms['client-form']!;
    expect(merged.expectedVersion, 7);
    expect(merged.dirty, isTrue);
    expect(merged.conflict, isNull);
  });
}
