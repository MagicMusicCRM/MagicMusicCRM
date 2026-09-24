import 'package:magic_music_crm/core/navigation/entity_link.dart';

/// Only supported entity payloads may open a route; chat payloads use the
/// existing messenger navigation path.
EntityLink? notificationTapTarget(Map<String, dynamic> data) {
  final link = EntityLink.fromJson({
    'entityType': data['entityType'],
    'entityId': data['entityId'],
  });
  return link.isSupported ? link : null;
}
