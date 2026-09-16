import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'notification startup has one permission requester, including denial',
    () {
      final source = File(
        'lib/core/services/notification_service.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('Permission.notification.request()')));
      expect(
        RegExp(
          r'_firebaseMessaging\.requestPermission\(',
        ).allMatches(source).length,
        1,
      );
    },
  );
}
