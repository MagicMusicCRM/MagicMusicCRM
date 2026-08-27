import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/forms/dirty_form_exit.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/crm_nav_rbac.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/providers/chat_providers.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/alert_policy.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/core/services/section_unseen_service.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_runtime.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_view.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';
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
  late final ProductionWorkspaceRuntime _runtime;
  final _sectionEffect = _WorkspaceSectionEffect();
  final Map<WorkspaceTabState, _DirtyRuntimeLease> _dirtyLeases =
      HashMap.identity();
  var _isDesktop = false;

  WorkspaceController get _controller => _runtime.controller;

  @override
  void initState() {
    super.initState();
    final store = ref.read(accountWorkspaceStoreProvider);
    _runtime = ProductionWorkspaceRuntime(
      snapshot: widget.snapshot,
      initialLink: widget.initialLink,
      store: store,
      logoutCoordinator: ref.read(workspaceLogoutCoordinatorProvider),
      realtime: ref.read(magicRealtimeServiceProvider),
    );
  }

  @override
  void didUpdateWidget(covariant ProductionWorkspaceHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _runtime.update(snapshot: widget.snapshot, initialLink: widget.initialLink);
  }

  @override
  void dispose() {
    _runtime.dispose();
    super.dispose();
  }

  Future<DirtyCloseDecision> _resolveDirty(WorkspaceTabState tab) async {
    final lease = _DirtyRuntimeLease(_controller, _runtime.generation);
    _dirtyLeases[tab] = lease;
    final decision = switch (await showDirtyFormExitDialog(context)) {
      DirtyFormExitDecision.save => DirtyCloseDecision.save,
      DirtyFormExitDecision.discard => DirtyCloseDecision.discard,
      DirtyFormExitDecision.cancel || null => DirtyCloseDecision.cancel,
    };
    if (!_runtime.owns(lease.controller, lease.generation)) {
      _removeLease(tab, lease);
      return DirtyCloseDecision.cancel;
    }
    if (decision == DirtyCloseDecision.cancel) _removeLease(tab, lease);
    return decision;
  }

  Future<void> _saveDirty(WorkspaceTabState tab) async {
    final lease = _dirtyLeases.remove(tab);
    _requireCurrent(lease);
    await lease!.controller.saveDirtyForms(tab);
    _requireCurrent(lease);
  }

  Future<void> _discardDirty(WorkspaceTabState tab) async {
    final lease = _dirtyLeases.remove(tab);
    _requireCurrent(lease);
    await lease!.controller.discardDirtyForms(tab);
    _requireCurrent(lease);
  }

  void _requireCurrent(_DirtyRuntimeLease? lease) {
    if (lease == null || !_runtime.owns(lease.controller, lease.generation)) {
      throw StateError('Workspace runtime changed during dirty resolution.');
    }
  }

  void _removeLease(WorkspaceTabState tab, _DirtyRuntimeLease lease) {
    if (identical(_dirtyLeases[tab], lease)) _dirtyLeases.remove(tab);
  }

  Future<void> _afterDirty(
    WorkspaceTabState tab,
    void Function(WorkspaceController controller) navigate,
  ) async {
    final controller = _controller;
    final generation = _runtime.generation;
    final allowed = await controller.resolveDirtyTab(
      tab.tabId,
      resolveDirty: _resolveDirty,
      saveDirty: _saveDirty,
      discardDirty: _discardDirty,
    );
    if (allowed && _runtime.owns(controller, generation)) navigate(controller);
  }

  Future<void> _back(WorkspaceTabState tab) =>
      _afterDirty(tab, (controller) => controller.back(tab.tabId));

  Future<void> _navigate(WorkspaceTabState tab, AppBreadcrumbNode node) =>
      _afterDirty(tab, (controller) => controller.push(tab.tabId, node.link));

  void _selectSection(int tab) {
    final link = EntityRouteRegistry.sectionRootLink(
      crmSectionForTab(widget.snapshot.role, tab),
    );
    _controller.replaceCurrentLink(_controller.state.activeTabId, link);
  }

  @override
  Widget build(BuildContext context) {
    _bindWorkspaceProviders(
      ref,
      isMounted: () => mounted,
      controller: () => _controller,
      onCrmRequest: (request) => _routeCrmRequest(
        context,
        widget.snapshot,
        _controller,
        request,
        isDesktop: _isDesktop,
        onLimitReached: _showLimit,
      ),
    );
    final unseen = ref.watch(sectionUnseenProvider).asData?.value ?? const {};
    return ProductionWorkspaceView(
      controller: _controller,
      tabBuilder: widget.tabBuilder,
      navigationFor: (tab, {required isDesktop}) => _workspaceNavigation(
        widget.snapshot,
        tab,
        isDesktop: isDesktop,
        unseen: unseen,
      ),
      locationFor: (tab) => EntityRouteRegistry()
          .resolve(tab.currentRoute.link, widget.snapshot)
          .canonicalLocation,
      onLayoutModeChanged: (value) => _isDesktop = value,
      onTabVisible: (tab, {required isDesktop}) => _sectionEffect.onVisible(
        ref,
        snapshot: widget.snapshot,
        tab: tab,
        isDesktop: isDesktop,
        runtimeGeneration: _runtime.generation,
        isMounted: () => mounted,
      ),
      onSectionSelected: _selectSection,
      onBack: _back,
      onNavigate: _navigate,
      onLimitReached: _showLimit,
      resolveDirty: _resolveDirty,
      saveDirty: _saveDirty,
      discardDirty: _discardDirty,
    );
  }

  void _showLimit() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Можно открыть не больше 10 вкладок.')),
    );
  }
}

class _DirtyRuntimeLease {
  const _DirtyRuntimeLease(this.controller, this.generation);

  final WorkspaceController controller;
  final int generation;
}

ProductionWorkspaceNavigationData _workspaceNavigation(
  CapabilitySnapshot snapshot,
  WorkspaceTabState tab, {
  required bool isDesktop,
  required Map<String, int> unseen,
}) {
  final visible = crmVisibleTabsForCapabilities(snapshot, isDesktop: isDesktop);
  final requested =
      crmTabForEntityLink(tab.currentRoute.link, snapshot.role) ??
      visible.first;
  final selected = crmResolveVisibleTab(
    visibleTabs: visible,
    requestedTab: requested,
    currentTab: visible.first,
  );
  return ProductionWorkspaceNavigationData(
    sectionTabs: visible,
    destinations: [
      for (final sectionTab in visible)
        crmDestinationForTab(
          snapshot.role,
          sectionTab,
          badgeCount: unseen[sectionKeyForTab(sectionTab)] ?? 0,
        ),
    ],
    selectedIndex: visible.indexOf(selected),
  );
}

class _WorkspaceSectionEffect {
  String? _lastMarkedSection;
  (String, int)? _token;

  void onVisible(
    WidgetRef ref, {
    required CapabilitySnapshot snapshot,
    required WorkspaceTabState tab,
    required bool isDesktop,
    required int runtimeGeneration,
    required bool Function() isMounted,
  }) {
    final token = (snapshot.accountId, runtimeGeneration);
    if (_token != token) {
      _token = token;
      _lastMarkedSection = null;
    }
    final navigation = _workspaceNavigation(
      snapshot,
      tab,
      isDesktop: isDesktop,
      unseen: const {},
    );
    final selected = navigation.sectionTabs[navigation.selectedIndex];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted() || _token != token) return;
      ref.read(activeViewProvider.notifier).set(crmTab: selected, chatId: null);
      final section = sectionKeyForTab(selected);
      if (section == null) {
        _lastMarkedSection = null;
      } else if (section != _lastMarkedSection) {
        _lastMarkedSection = section;
        unawaited(
          ref
              .read(sectionUnseenServiceProvider)
              .markSeen(section)
              .then((_) {
                if (isMounted() && _token == token) {
                  ref.invalidate(sectionUnseenProvider);
                }
              })
              .catchError((_) {}),
        );
      }
    });
  }
}

void _bindWorkspaceProviders(
  WidgetRef ref, {
  required bool Function() isMounted,
  required WorkspaceController Function() controller,
  required ValueChanged<CrmNavigationRequest> onCrmRequest,
}) {
  ref.listen(crmRealtimeProvider, (previous, next) {
    final event = next.value;
    if (event != null &&
        isMounted() &&
        !event.isFallbackPoll &&
        sectionForEntity(event.entity) != null) {
      ref.invalidate(sectionUnseenProvider);
    }
  });
  ref.listen<CrmNavigationRequest?>(crmNavigationRequestProvider, (_, next) {
    if (next == null || !isMounted()) return;
    onCrmRequest(next);
    Future.microtask(
      () => ref.read(crmNavigationRequestProvider.notifier).clear(),
    );
  });
  ref.listen<MessengerNavigationState?>(messengerNavigationProvider, (_, next) {
    if (next == null || !isMounted()) return;
    final current = controller();
    if (current.state.activeTab.currentRoute.link.entityType !=
        EntityLinkType.chat) {
      current.replaceCurrentLink(
        current.state.activeTabId,
        EntityRouteRegistry.sectionRootLink('chat'),
      );
    }
  });
}

void _routeCrmRequest(
  BuildContext context,
  CapabilitySnapshot snapshot,
  WorkspaceController controller,
  CrmNavigationRequest request, {
  required bool isDesktop,
  required VoidCallback onLimitReached,
}) {
  if (!isDesktop) {
    unawaited(
      navigateEntityLink(
        context,
        snapshot,
        request.link,
        target: request.openInNewTab
            ? EntityOpenTarget.newTab
            : EntityOpenTarget.current,
        sourceViewState: request.sourceState,
      ),
    );
    return;
  }
  final resolution = EntityRouteRegistry().resolve(request.link, snapshot);
  if (!resolution.canOpen) {
    unawaited(navigateEntityLink(context, snapshot, request.link));
    return;
  }
  try {
    controller.updateCurrentView(
      controller.state.activeTabId,
      request.sourceState,
    );
    final tabId = controller.open(
      request.link,
      titleHint: resolution.canonicalLocation?.title,
      explicitNew: request.openInNewTab,
    );
    controller.replaceCurrentLink(
      tabId,
      request.link,
      viewState: ContextViewState(
        filters: request.link.optionalFocus?.filter ?? const {},
        date: request.sourceState.date,
      ),
    );
  } on WorkspaceLimitReached {
    onLimitReached();
  }
}
