import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';

Future<EntityRouteResolution> openEntityLink(
  BuildContext context,
  WidgetRef ref,
  EntityLink link, {
  EntityRouteRegistry? registry,
}) async {
  final snapshot = await ref.read(capabilitySnapshotProvider.future);
  final resolution = (registry ?? EntityRouteRegistry()).resolve(
    link,
    snapshot,
  );
  if (!context.mounted) return resolution;
  if (resolution.canOpen) {
    await context.push<void>(resolution.location!);
    return resolution;
  }

  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Связанная запись недоступна.')));
  return resolution;
}
