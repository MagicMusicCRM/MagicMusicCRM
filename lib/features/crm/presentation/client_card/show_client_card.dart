import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_shell.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_page_state.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';

import 'client_card.dart';
import 'teacher_client_card.dart';

/// Compatibility launcher retained for existing list/board callers. It now
/// opens the canonical routed client workspace instead of a second dialog.
Future<bool?> showClientCard(
  BuildContext context, {
  required String entityType,
  required String entityId,
  Map<String, dynamic>? seed,
}) async {
  final link = EntityLink.typed(
    entityType: EntityLinkType.client,
    entityId: entityId,
    variant: entityType == 'lead' ? 'lead' : 'student',
  );
  final container = ProviderScope.containerOf(context, listen: false);
  final snapshot = await container.read(capabilitySnapshotProvider.future);
  if (!context.mounted) return null;
  final resolution = EntityRouteRegistry().resolve(link, snapshot);
  if (!resolution.canOpen) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Карточка клиента недоступна.')),
    );
    return null;
  }
  final workspace = WorkspaceNavigationScope.maybeOf(context);
  if (workspace?.isDesktop == true) {
    workspace!.controller.push(workspace.controller.state.activeTabId, link);
    return null;
  }
  return context.push<bool>(resolution.location!);
}

class ClientCardRouteScreen extends StatelessWidget {
  const ClientCardRouteScreen({
    required this.entityType,
    required this.entityId,
    this.initialSection = 'overview',
    super.key,
  });

  final String entityType;
  final String entityId;
  final String initialSection;

  @override
  Widget build(BuildContext context) {
    return CapabilityShellGate(
      builder: (_, snapshot) => Scaffold(
        body: SafeArea(
          child: ClientCardRouteSurface(
            snapshot: snapshot,
            entityType: entityType,
            entityId: entityId,
            initialSection: initialSection,
          ),
        ),
      ),
    );
  }
}

class ClientCardRouteSurface extends StatelessWidget {
  const ClientCardRouteSurface({
    required this.snapshot,
    required this.entityType,
    required this.entityId,
    this.initialSection = 'overview',
    this.viewState,
    super.key,
  });

  final CapabilitySnapshot snapshot;
  final String entityType;
  final String entityId;
  final String initialSection;
  final ContextViewState? viewState;

  @override
  Widget build(BuildContext context) {
    if (!snapshot.allows('crm.client.read.basic')) {
      return const Material(
        child: MagicPageState(
          kind: MagicPageStateKind.forbidden,
          title: 'Карточка клиента недоступна',
          message: 'У вашей роли нет доступа к этой карточке.',
        ),
      );
    }
    final workspace = WorkspaceNavigationScope.maybeOf(context);
    final routedSection =
        viewState?.filters['section']?.toString() ?? initialSection;
    void close(bool? result) {
      if (workspace?.isDesktop == true) {
        final controller = workspace!.controller;
        final tab = controller.state.activeTab;
        if (tab.routeStack.length > 1) {
          controller.back(tab.tabId);
        } else {
          controller.push(
            tab.tabId,
            EntityLink.typed(
              entityType: EntityLinkType.clientStatus,
              entityId: '__section__',
              optionalFocus: EntityLinkFocus(focus: 'section'),
            ),
          );
        }
        return;
      }
      Navigator.of(context).pop(result);
    }

    void sectionChanged(String section) {
      if (workspace?.isDesktop == true) {
        final controller = workspace!.controller;
        final tab = controller.state.activeTab;
        final current = tab.currentRoute.viewState;
        controller.updateCurrentView(
          tab.tabId,
          ContextViewState(
            filters: {...current.filters, 'section': section},
            date: current.date,
            scrollOffset: current.scrollOffset,
            selectedColumn: current.selectedColumn,
          ),
        );
        return;
      }
      final router = GoRouter.of(context);
      final current = router.routerDelegate.currentConfiguration.uri;
      router.replace(
        Uri(
          path: current.path,
          queryParameters: {...current.queryParameters, 'section': section},
        ).toString(),
      );
    }

    if (snapshot.role == 'teacher') {
      return Material(
        child: TeacherClientCard(
          entityType: entityType,
          entityId: entityId,
          routed: true,
          onClose: () => close(null),
        ),
      );
    }
    return Material(
      child: ClientCard(
        lead: {'id': entityId},
        entityType: entityType,
        routed: true,
        initialSection: routedSection,
        onSectionChanged: sectionChanged,
        onClose: close,
      ),
    );
  }
}
