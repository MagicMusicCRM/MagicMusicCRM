import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/admin/presentation/screens/profile_detail_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/access_editor_sheet.dart';

Widget? buildStaffWorkspaceSurface({
  required CapabilitySnapshot snapshot,
  required ContextRouteState route,
  required String tabId,
}) {
  final client = buildClientWorkspaceSurface(
    snapshot: snapshot,
    route: route,
    tabId: tabId,
  );
  if (client != null) return client;

  final link = route.link;
  if (link.entityType != EntityLinkType.user ||
      !snapshot.allows('system.settings.manage') ||
      link.entityId == '__section__' ||
      link.entityId == 'user-search') {
    return null;
  }
  if (link.optionalFocus?.focus == 'permissions') {
    return AccessEditorSheet(
      actorRole: snapshot.role,
      userId: link.entityId,
      userLabel: link.presentation?.primary ?? 'Пользователь',
      embedded: true,
    );
  }
  return ProfileDetailScreen(profileId: link.entityId, embedded: true);
}
