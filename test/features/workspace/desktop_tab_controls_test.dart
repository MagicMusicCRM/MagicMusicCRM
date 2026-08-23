import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_presentation_resolver.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';

class _TabDraftProbe extends StatefulWidget {
  const _TabDraftProbe({required this.tabId});

  final String tabId;

  @override
  State<_TabDraftProbe> createState() => _TabDraftProbeState();
}

class _TabDraftProbeState extends State<_TabDraftProbe> {
  final controller = TextEditingController();
  bool detailsOpen = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          key: ValueKey('draft-${widget.tabId}'),
          controller: controller,
        ),
        TextButton(
          key: ValueKey('details-${widget.tabId}'),
          onPressed: () => setState(() => detailsOpen = !detailsOpen),
          child: const Text('Вложенное окно'),
        ),
        if (detailsOpen) Text('Открыто ${widget.tabId}'),
      ],
    );
  }
}

void main() {
  EntityLink link(String id) =>
      EntityLink.typed(entityType: EntityLinkType.client, entityId: id);

  WorkspaceController controller() => WorkspaceController(
    accountId: 'account-1',
    initialLink: link('home'),
    titleResolver: const EntityPresentationResolver().pageTitle,
    sharedScope: WorkspaceSharedScope(
      session: Object(),
      cache: Object(),
      realtime: Object(),
    ),
  );

  testWidgets('linked open-new reports the ten-tab limit', (tester) async {
    final workspace = controller();
    for (var index = 1; index < WorkspaceController.maxTabs; index++) {
      workspace.open(link('client-$index'), explicitNew: true);
    }
    var limitReached = false;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceLinkedEntityButton(
          controller: workspace,
          link: link('client-11'),
          label: 'Клиент 11',
          onLimitReached: () => limitReached = true,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('workspace-linked-client-client-11')),
    );
    expect(limitReached, isTrue);
    expect(workspace.state.tabs, hasLength(10));
  });

  test('reorder is persisted with active selection', () async {
    final workspace = controller();
    workspace.open(link('client-1'));
    workspace.open(link('client-2'));
    final active = workspace.state.activeTabId;
    final backend = InMemoryWorkspaceKeyValueStore();
    final store = AccountWorkspaceStore(backend);
    final binding = WorkspacePersistenceBinding(
      controller: workspace,
      store: store,
    );

    workspace.reorderTab(2, 0);
    await binding.flush();
    final restored = await store.restore(
      accountId: 'account-1',
      fallback: controller().state,
      routeAllowed: (_) => true,
    );

    expect(restored.activeTabId, active);
    expect(restored.tabs.map((tab) => tab.currentRoute.link.entityId), [
      'client-2',
      'home',
      'client-1',
    ]);
    binding.dispose();
  });

  testWidgets('tabs expose a trailing plus and permanent close buttons', (
    tester,
  ) async {
    final workspace = controller();
    final clientTab = workspace.open(link('client-1'), titleHint: 'Клиент');
    final lastTab = workspace.open(link('client-2'), titleHint: 'Другой');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopWorkspaceShell(
            controller: workspace,
            tabBuilder: (context, tab) => Text(tab.titleHint),
          ),
        ),
      ),
    );

    final plus = find.byKey(const ValueKey('workspace-new-tab'));
    final lastClose = find.byKey(ValueKey('workspace-tab-close-$lastTab'));
    expect(plus, findsOneWidget);
    expect(lastClose, findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(find.byTooltip('Прокрутить вкладки влево'), findsNothing);
    expect(find.byTooltip('Прокрутить вкладки вправо'), findsNothing);
    expect(
      tester.getCenter(plus).dx,
      greaterThan(tester.getCenter(lastClose).dx),
    );

    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(workspace.state.tabs, hasLength(4));

    await tester.tap(find.byKey(ValueKey('workspace-tab-close-$clientTab')));
    await tester.pumpAndSettle();
    expect(workspace.state.tabs, hasLength(3));
    expect(workspace.state.tabs.any((tab) => tab.tabId == clientTab), isFalse);
  });

  testWidgets('narrow tab strip scrolls without arrows or a visible bar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 400);
    addTearDown(tester.view.reset);
    final workspace = controller();
    for (var index = 1; index < WorkspaceController.maxTabs; index++) {
      workspace.open(
        link('client-$index'),
        titleHint: 'Длинная вкладка $index',
        explicitNew: true,
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopWorkspaceShell(
            controller: workspace,
            tabBuilder: (context, tab) => Text(tab.titleHint),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tabs = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    final scrollController = tabs.scrollController!;
    expect(scrollController.position.maxScrollExtent, greaterThan(0));
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byTooltip('Прокрутить вкладки влево'), findsNothing);
    expect(find.byTooltip('Прокрутить вкладки вправо'), findsNothing);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ReorderableListView)),
        scrollDelta: const Offset(200, 0),
      ),
    );
    await tester.pump();
    expect(scrollController.offset, greaterThan(0));
  });

  testWidgets('tab switch keeps local draft and nested state mounted', (
    tester,
  ) async {
    final workspace = controller();
    final first = workspace.state.activeTabId;
    final second = workspace.open(link('client-2'), titleHint: 'Вторая');
    workspace.selectTab(first);
    workspace.registerForm(first, 'editor', draft: const {'name': 'Анна'});
    workspace.updateForm(first, 'editor', dirty: true);
    var exitRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopWorkspaceShell(
            controller: workspace,
            resolveDirty: (_) async {
              exitRequests++;
              return DirtyCloseDecision.discard;
            },
            tabBuilder: (_, tab) => _TabDraftProbe(tabId: tab.tabId),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(ValueKey('draft-$first')),
      'Несохранённый текст',
    );
    await tester.tap(find.byKey(ValueKey('details-$first')));
    await tester.pump();
    expect(find.text('Открыто $first'), findsOneWidget);

    final secondTab = find.byKey(ValueKey('workspace-tab-select-$second'));
    await tester.tap(secondTab);
    await tester.pump();
    expect(workspace.state.activeTabId, second);
    expect(exitRequests, 0);
    expect(workspace.state.tabs.first.forms['editor']!.dirty, isTrue);

    await tester.enterText(
      find.byKey(ValueKey('draft-$second')),
      'Текст второй вкладки',
    );
    await tester.tap(find.byKey(ValueKey('workspace-tab-select-$first')));
    await tester.pump();

    final firstDraft = tester.widget<TextField>(
      find.byKey(ValueKey('draft-$first')),
    );
    expect(firstDraft.controller!.text, 'Несохранённый текст');
    expect(find.text('Открыто $first'), findsOneWidget);
    expect(exitRequests, 0);
  });

  test(
    'dirty close supports Save, Discard and Cancel without silent loss',
    () async {
      final workspace = controller();
      String dirtyTab(String id) {
        final tab = workspace.open(link(id), explicitNew: true);
        workspace.registerForm(tab, 'form-$id', draft: {'name': 'draft-$id'});
        workspace.updateForm(tab, 'form-$id', dirty: true);
        return tab;
      }

      final cancelTab = dirtyTab('cancel');
      expect(
        await workspace.closeTab(
          cancelTab,
          resolveDirty: (_) async => DirtyCloseDecision.cancel,
          saveDirty: (_) async => fail('cancel must not save'),
        ),
        isFalse,
      );
      expect(workspace.state.tabs.any((tab) => tab.tabId == cancelTab), isTrue);

      final untouchedTab = dirtyTab('untouched');
      await workspace.closeOtherTabs(
        workspace.state.tabs.first.tabId,
        resolveDirty: (tab) async => tab.tabId == cancelTab
            ? DirtyCloseDecision.cancel
            : DirtyCloseDecision.discard,
        saveDirty: (_) async {},
      );
      expect(
        workspace.state.tabs.any((tab) => tab.tabId == untouchedTab),
        isTrue,
      );

      final saved = <String>[];
      final saveTab = dirtyTab('save');
      expect(
        await workspace.closeTab(
          saveTab,
          resolveDirty: (_) async => DirtyCloseDecision.save,
          saveDirty: (tab) async => saved.add(tab.tabId),
        ),
        isTrue,
      );
      expect(saved, [saveTab]);

      final discardTab = dirtyTab('discard');
      expect(
        await workspace.closeTab(
          discardTab,
          resolveDirty: (_) async => DirtyCloseDecision.discard,
          saveDirty: (_) async => fail('discard must not save'),
        ),
        isTrue,
      );
    },
  );

  test('failed workspace Save preserves draft version and conflict', () async {
    final workspace = controller();
    final tabId = workspace.state.activeTabId;
    workspace.registerForm(
      tabId,
      'editor',
      expectedVersion: 7,
      draft: const {'name': 'Анна', 'idempotencyKey': 'stable-key'},
    );
    workspace.updateForm(tabId, 'editor', dirty: true);
    workspace.markFormConflict(
      tabId,
      'editor',
      serverVersion: 8,
      source: 'realtime',
    );

    final allowed = await workspace.resolveDirtyTab(
      tabId,
      resolveDirty: (_) async => DirtyCloseDecision.save,
      saveDirty: (_) async => throw StateError('network failed'),
    );

    expect(allowed, isFalse);
    final form = workspace.state.activeTab.forms['editor']!;
    expect(form.dirty, isTrue);
    expect(form.expectedVersion, 7);
    expect(form.conflict!.serverVersion, 8);
    expect(form.draft, {'name': 'Анна', 'idempotencyKey': 'stable-key'});
  });
}
