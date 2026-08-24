import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';

/// Opens the canonical routed client workspace for list and board callers.
Future<bool?> showClientCard(
  BuildContext context, {
  required String entityType,
  required String entityId,
  Map<String, dynamic>? seed,
  String? presentationLabel,
}) async {
  final label = presentationLabel?.trim().isNotEmpty == true
      ? presentationLabel!.trim()
      : _clientPresentationLabel(seed);
  final link = EntityLink.typed(
    entityType: EntityLinkType.client,
    entityId: entityId,
    variant: entityType == 'lead' ? 'lead' : 'student',
    presentation: label == null
        ? null
        : EntityPresentationReference(primary: label),
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

String? _clientPresentationLabel(Map<String, dynamic>? seed) {
  if (seed == null) return null;
  final display =
      [
            seed['displayName'],
            seed['display_name'],
            seed['fullName'],
            seed['full_name'],
          ]
          .map((value) => value?.toString().trim() ?? '')
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  if (display.isNotEmpty) return display;
  final first = (seed['first_name'] ?? seed['name'])?.toString().trim() ?? '';
  final last = seed['last_name']?.toString().trim() ?? '';
  final name = [last, first].where((value) => value.isNotEmpty).join(' ');
  return name.isEmpty ? null : name;
}
