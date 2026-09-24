import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot_model.dart';

void main() {
  const client = CapabilitySnapshot(
    accountId: 'client-a',
    role: 'client',
    accessVersion: 1,
    capabilities: {
      'schedule.lesson.read.assigned',
      'commerce.client_finance.read',
    },
    scopes: {},
  );
  const teacher = CapabilitySnapshot(
    accountId: 'teacher-a',
    role: 'teacher',
    accessVersion: 1,
    capabilities: {'schedule.lesson.read.assigned'},
    scopes: {},
  );

  test('client notification links open the matching client section', () {
    final registry = EntityRouteRegistry();
    for (final (type, section) in [
      (EntityLinkType.lesson, 'lessons'),
      (EntityLinkType.subscription, 'subscription'),
      (EntityLinkType.payment, 'subscription'),
    ]) {
      final route = registry.resolve(
        EntityLink.typed(entityType: type, entityId: 'record-a'),
        client,
      );
      expect(route.canOpen, isTrue);
      expect(route.location, '/client?section=$section');
    }
  });

  test('capability gate still rejects finance links for teacher', () {
    final route = EntityRouteRegistry().resolve(
      EntityLink.typed(entityType: EntityLinkType.payment, entityId: 'pay-a'),
      teacher,
    );
    expect(route.canOpen, isFalse);
  });
}
