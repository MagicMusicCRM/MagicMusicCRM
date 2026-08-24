import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/workspace/entity_navigation_scope.dart';

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
    final workspace = EntityNavigationScope.maybeOf(context);
    if (workspace?.isDesktop == true) {
      if (sourceViewState != null) {
        workspace!.preserveCurrentView(sourceViewState);
      }
      final openResult = workspace!.open(
        link,
        titleHint: resolution.canonicalLocation?.title,
      );
      if (openResult == EntityNavigationOpenResult.limitReached) {
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
