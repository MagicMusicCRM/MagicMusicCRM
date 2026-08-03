import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';

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
      _disposeController();
      _initialize();
    }
  }

  void _initialize() {
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
    );
    _logoutCoordinator.attach(_controller);
    _persistence = WorkspacePersistenceBinding(
      controller: _controller,
      store: store,
    );
    unawaited(
      store
          .restore(
            accountId: widget.snapshot.accountId,
            fallback: _controller.state,
            routeAllowed: (link) =>
                registry.resolve(link, widget.snapshot).canOpen,
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 840) {
          return ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              if (_controller.state.loggedOut) {
                return const SizedBox.shrink();
              }
              return widget.tabBuilder(context, _controller.state.activeTab);
            },
          );
        }
        return DesktopWorkspaceShell(
          controller: _controller,
          tabBuilder: widget.tabBuilder,
          onLimitReached: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Можно открыть не больше 10 вкладок.'),
              ),
            );
          },
        );
      },
    );
  }
}
