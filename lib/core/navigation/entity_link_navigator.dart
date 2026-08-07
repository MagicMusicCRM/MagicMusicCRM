import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';

enum EntityOpenTarget { current, newTab }

Future<EntityRouteResolution> openEntityLink(
  BuildContext context,
  WidgetRef ref,
  EntityLink link, {
  EntityRouteRegistry? registry,
  EntityOpenTarget target = EntityOpenTarget.current,
  ContextViewState? sourceViewState,
  EntityLifecycleState lifecycle = EntityLifecycleState.active,
}) async {
  final snapshot = await ref.read(capabilitySnapshotProvider.future);
  if (!context.mounted) {
    return (registry ?? EntityRouteRegistry()).resolve(
      link,
      snapshot,
      lifecycle: lifecycle,
    );
  }
  return navigateEntityLink(
    context,
    snapshot,
    link,
    registry: registry,
    target: target,
    sourceViewState: sourceViewState,
    lifecycle: lifecycle,
  );
}

Future<EntityRouteResolution> navigateEntityLink(
  BuildContext context,
  CapabilitySnapshot snapshot,
  EntityLink link, {
  EntityRouteRegistry? registry,
  EntityOpenTarget target = EntityOpenTarget.current,
  ContextViewState? sourceViewState,
  EntityLifecycleState lifecycle = EntityLifecycleState.active,
}) async {
  final resolution = (registry ?? EntityRouteRegistry()).resolve(
    link,
    snapshot,
    lifecycle: lifecycle,
  );
  if (!context.mounted) return resolution;
  if (resolution.canOpen) {
    final workspace = WorkspaceNavigationScope.maybeOf(context);
    if (workspace?.isDesktop == true) {
      try {
        final controller = workspace!.controller;
        if (sourceViewState != null) {
          controller.updateCurrentView(
            controller.state.activeTabId,
            sourceViewState,
          );
        }
        controller.open(
          link,
          titleHint: resolution.canonicalLocation?.title,
          explicitNew: true,
        );
      } on WorkspaceLimitReached {
        _showMessage(context, 'Можно открыть не больше 10 вкладок.');
      }
      return resolution;
    }
    await context.push<void>(resolution.location!);
    return resolution;
  }

  final presentation = resolution.presentation;
  _showMessage(
    context,
    resolution.state == EntityRouteState.forbidden ||
            resolution.state == EntityRouteState.unknown
        ? '${presentation.primary}.'
        : [
            presentation.primary,
            if (presentation.context?.isNotEmpty == true) presentation.context!,
          ].join(' · '),
  );
  return resolution;
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
