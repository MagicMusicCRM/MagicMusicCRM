import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/services/notification_tap_target.dart';

void main() {
  test('push entity payloads resolve to their intended records', () {
    for (final type in ['lead', 'lesson', 'task', 'subscription']) {
      final target = notificationTapTarget({
        'entityType': type,
        'entityId': 'record-a',
      });
      expect(target?.entityId, 'record-a');
      expect(target?.isSupported, isTrue);
    }
  });

  test('chat and malformed payloads do not open an unrelated entity', () {
    expect(notificationTapTarget({'sender_id': 'user-a'}), isNull);
    expect(notificationTapTarget({'entityType': 'lesson'}), isNull);
    expect(
      notificationTapTarget({'entityType': 'unknown', 'entityId': 'x'}),
      isNull,
    );
    expect(
      notificationTapTarget({
        'entityType': 'task',
        'entityId': 'task-a',
      })?.entityType,
      EntityLinkType.task,
    );
  });
}
