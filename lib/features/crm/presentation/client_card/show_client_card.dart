import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_shell.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';

export 'client_card_launcher.dart';

import 'client_card.dart';
import 'teacher_client_card.dart';

Widget? buildClientWorkspaceSurface({
  required CapabilitySnapshot snapshot,
  required ContextRouteState route,
  required String tabId,
}) {
  final link = route.link;
  final isClient = link.entityType == EntityLinkType.client;
  final isClientCommerce =
      link.entityType == EntityLinkType.payment ||
      link.entityType == EntityLinkType.subscription;
  final studentId = isClientCommerce
      ? link.optionalFocus?.filter['studentId']?.toString()
      : null;
  if (!isClient && (studentId == null || studentId.isEmpty)) return null;
  final filter = {...route.viewState.filters, ...?link.optionalFocus?.filter};
  final section =
      filter['section']?.toString() ??
      (link.entityType == EntityLinkType.payment
          ? 'payments'
          : link.entityType == EntityLinkType.subscription
          ? 'subscriptions'
          : 'overview');
  final entityType = isClient && link.rawEntityType == 'lead'
      ? 'lead'
      : 'student';
  final entityId = isClient ? link.entityId : studentId!;
  return ClientCardRouteSurface(
    key: ValueKey('workspace-client-$tabId-$entityType-$entityId'),
    snapshot: snapshot,
    entityType: entityType,
    entityId: entityId,
    initialSection: section,
    workspaceTabId: tabId,
    viewState: ContextViewState(
      filters: filter,
      date: route.viewState.date,
      scrollOffset: route.viewState.scrollOffset,
      selectedColumn: route.viewState.selectedColumn,
    ),
  );
}

class ClientCardRouteScreen extends StatelessWidget {
  const ClientCardRouteScreen({
    required this.entityType,
    required this.entityId,
    this.initialSection = 'overview',
    this.initialViewState,
    super.key,
  });

  final String entityType;
  final String entityId;
  final String initialSection;
  final ContextViewState? initialViewState;

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
            viewState: initialViewState,
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
    this.workspaceTabId,
    super.key,
  });

  final CapabilitySnapshot snapshot;
  final String entityType;
  final String entityId;
  final String initialSection;
  final ContextViewState? viewState;
  final String? workspaceTabId;

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
    Uri clientUri(Map<String, String> queryParameters) => Uri(
      pathSegments: ['', entityType == 'lead' ? 'leads' : 'students', entityId],
      queryParameters: queryParameters,
    );
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
      final current = GoRouterState.of(context).uri;
      router.replace(
        clientUri({...current.queryParameters, 'section': section}).toString(),
      );
    }

    void viewStateChanged(ContextViewState next) {
      if (workspace?.isDesktop == true) {
        final controller = workspace!.controller;
        controller.updateCurrentView(controller.state.activeTabId, next);
        return;
      }
      final router = GoRouter.of(context);
      final current = GoRouterState.of(context).uri;
      router.replace(
        clientUri({
          ...current.queryParameters,
          'section': 'lessons',
          if (next.filters['clientCalendarMode'] case final String mode)
            'calendarMode': mode,
          if (next.filters['clientCalendarBranchId'] case final String branch)
            'branchId': branch,
          if (next.date != null)
            'calendarDate': DateFormat('yyyy-MM-dd').format(next.date!),
        }).toString(),
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
        workspaceTabId: workspaceTabId,
        capabilitySnapshot: snapshot,
        initialViewState: viewState,
        onViewStateChanged: viewStateChanged,
        onSectionChanged: sectionChanged,
        onClose: close,
      ),
    );
  }
}
