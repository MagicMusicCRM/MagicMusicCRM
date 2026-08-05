import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/magic_context_bar.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/core/widgets/v7/dirty_form_exit.dart';

class ProductionWorkspaceHost extends ConsumerStatefulWidget {
  const ProductionWorkspaceHost({
    required this.snapshot,
    required this.tabBuilder,
    this.initialLink,
    super.key,
  });

  final CapabilitySnapshot snapshot;
  final EntityLink? initialLink;
  final WorkspaceTabBuilder tabBuilder;

  @override
  ConsumerState<ProductionWorkspaceHost> createState() =>
      _ProductionWorkspaceHostState();
}

class _ProductionWorkspaceHostState
    extends ConsumerState<ProductionWorkspaceHost> {
  late WorkspaceController _controller;
  late WorkspacePersistenceBinding _persistence;
  late WorkspaceLogoutCoordinator _logoutCoordinator;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant ProductionWorkspaceHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.cacheKey != widget.snapshot.cacheKey) {
      final reset =
          oldWidget.snapshot.accountId != widget.snapshot.accountId ||
              oldWidget.snapshot.role != widget.snapshot.role
          ? _logoutCoordinator.logout(oldWidget.snapshot.accountId)
          : Future<void>.value();
      _disposeController();
      _initialize(beforeRestore: reset);
    } else if (!_sameLink(oldWidget.initialLink, widget.initialLink) &&
        widget.initialLink != null) {
      final resolution = EntityRouteRegistry().resolve(
        widget.initialLink!,
        widget.snapshot,
      );
      if (resolution.canOpen &&
          !_sameLink(
            _controller.state.activeTab.currentRoute.link,
            widget.initialLink,
          )) {
        _controller.push(_controller.state.activeTabId, widget.initialLink!);
      }
    }
  }

  void _initialize({Future<void>? beforeRestore}) {
    final generation = ++_generation;
    final store = ref.read(accountWorkspaceStoreProvider);
    _logoutCoordinator = ref.read(workspaceLogoutCoordinatorProvider);
    final registry = EntityRouteRegistry();
    final requested =
        widget.initialLink ??
        EntityLink.typed(entityType: EntityLinkType.chat, entityId: 'home');
    final initialLink = registry.resolve(requested, widget.snapshot).canOpen
        ? requested
        : EntityLink.typed(entityType: EntityLinkType.chat, entityId: 'home');
    final title =
        registry
            .resolve(initialLink, widget.snapshot)
            .canonicalLocation
            ?.title ??
        'Главная';
    _controller = WorkspaceController(
      accountId: widget.snapshot.accountId,
      initialLink: initialLink,
      initialTitle: title,
      sharedScope: WorkspaceSharedScope(
        session: widget.snapshot,
        cache: store,
        realtime: ref.read(magicRealtimeServiceProvider),
      ),
      titleResolver: (link) =>
          registry.resolve(link, widget.snapshot).canonicalLocation?.title ??
          'Главная',
    );
    _logoutCoordinator.attach(_controller);
    _persistence = WorkspacePersistenceBinding(
      controller: _controller,
      store: store,
    );
    unawaited(
      Future<void>.sync(() async {
            await beforeRestore;
          })
          .then(
            (_) => store.restore(
              accountId: widget.snapshot.accountId,
              fallback: _controller.state,
              routeAllowed: (link) =>
                  registry.resolve(link, widget.snapshot).canOpen,
            ),
          )
          .then((restored) {
            if (!mounted || generation != _generation) return;
            _controller.restore(restored);
          }),
    );
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    _generation++;
    _logoutCoordinator.detach(_controller);
    _persistence.dispose();
    _controller.dispose();
  }

  Future<DirtyCloseDecision> _resolveDirty(WorkspaceTabState tab) async {
    final decision = await showDirtyFormExitDialog(context);
    return switch (decision) {
      DirtyFormExitDecision.save => DirtyCloseDecision.save,
      DirtyFormExitDecision.discard => DirtyCloseDecision.discard,
      DirtyFormExitDecision.cancel || null => DirtyCloseDecision.cancel,
    };
  }

  Future<void> _saveDirty(WorkspaceTabState tab) =>
      _controller.saveDirtyForms(tab);

  Future<void> _discardDirty(WorkspaceTabState tab) =>
      _controller.discardDirtyForms(tab);

  Future<bool> _canLeaveTab(String tabId) {
    return _controller.resolveDirtyTab(
      tabId,
      resolveDirty: _resolveDirty,
      saveDirty: _saveDirty,
      discardDirty: _discardDirty,
    );
  }

  Future<void> _back(WorkspaceTabState tab) async {
    if (await _canLeaveTab(tab.tabId)) _controller.back(tab.tabId);
  }

  Future<void> _navigate(WorkspaceTabState tab, AppBreadcrumbNode node) async {
    if (await _canLeaveTab(tab.tabId)) {
      _controller.push(tab.tabId, node.link);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 840) {
          return WorkspaceNavigationScope(
            controller: _controller,
            isDesktop: false,
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                if (_controller.state.loggedOut) {
                  return const SizedBox.shrink();
                }
                return widget.tabBuilder(context, _controller.state.activeTab);
              },
            ),
          );
        }
        return WorkspaceNavigationScope(
          controller: _controller,
          isDesktop: true,
          child: DesktopWorkspaceShell(
            controller: _controller,
            tabBuilder: (context, tab) {
              final location = EntityRouteRegistry()
                  .resolve(tab.currentRoute.link, widget.snapshot)
                  .canonicalLocation;
              if (location == null) return widget.tabBuilder(context, tab);
              return Column(
                children: [
                  MagicContextBar(
                    controller: _controller,
                    tab: tab,
                    location: location,
                    currentTitle: tab.titleHint,
                    onBack: () => unawaited(_back(tab)),
                    onNavigate: (node) => unawaited(_navigate(tab, node)),
                  ),
                  Expanded(child: widget.tabBuilder(context, tab)),
                ],
              );
            },
            onLimitReached: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Можно открыть не больше 10 вкладок.'),
                ),
              );
            },
            resolveDirty: _resolveDirty,
            saveDirty: _saveDirty,
            discardDirty: _discardDirty,
          ),
        );
      },
    );
  }

  static bool _sameLink(EntityLink? left, EntityLink? right) {
    return left?.rawEntityType == right?.rawEntityType &&
        left?.entityId == right?.entityId &&
        left?.optionalFocus?.focus == right?.optionalFocus?.focus;
  }
}
