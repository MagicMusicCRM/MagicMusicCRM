import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/lead_notification_listener.dart';

void main() {
  test('manual Lead creation never raises the inbound Lead signal', () {
    const manual = CrmChangedEvent(
      entity: 'lead',
      action: 'created',
      id: 'lead-a',
    );
    expect(isInboundLeadNotificationForUser(manual, 'manager', 'user-a'), isFalse);
  });

  test('only an addressed inbound notification raises the desktop signal', () {
    const incoming = CrmChangedEvent(
      entity: 'notification',
      action: 'created',
      id: 'notification-a',
      notificationType: 'new_lead',
      affectedUserIds: ['user-a'],
    );
    expect(isInboundLeadNotificationForUser(incoming, 'manager', 'user-a'), isTrue);
    expect(isInboundLeadNotificationForUser(incoming, 'manager', 'user-b'), isFalse);
    expect(isInboundLeadNotificationForUser(incoming, 'teacher', 'user-a'), isFalse);
    expect(isInboundLeadNotificationForUser(
      const CrmChangedEvent(
        entity: 'notification',
        action: 'created',
        notificationType: 'task_assigned',
        affectedUserIds: ['user-a'],
      ),
      'manager',
      'user-a',
    ), isFalse);
  });
}
