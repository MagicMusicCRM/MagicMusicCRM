import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readProjectFile(String path) => File(path).readAsStringSync();

void main() {
  group('release metadata', () {
    test('Android package, label, and release signing gate are configured', () {
      final gradle = readProjectFile('android/app/build.gradle.kts');
      final manifest = readProjectFile(
        'android/app/src/main/AndroidManifest.xml',
      );

      expect(gradle, contains('applicationId = "magic.crm"'));
      expect(gradle, contains('Release signing is not configured'));
      expect(
        gradle,
        isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
      );
      expect(manifest, contains('android:label="Magic Music CRM"'));
      expect(manifest, contains('android.permission.INTERNET'));
      expect(
        manifest,
        contains(
          'android.permission.READ_EXTERNAL_STORAGE" tools:node="remove"',
        ),
      );
      expect(
        manifest,
        contains('android.permission.READ_MEDIA_IMAGES" tools:node="remove"'),
      );
      expect(
        manifest,
        contains('android.permission.READ_MEDIA_VIDEO" tools:node="remove"'),
      );
      expect(
        manifest,
        contains('android.permission.READ_MEDIA_AUDIO" tools:node="remove"'),
      );
      expect(
        manifest,
        isNot(contains('android.permission.WRITE_EXTERNAL_STORAGE')),
      );
    });

    test('Firebase app identifiers match immutable mobile package ids', () {
      final googleServices =
          jsonDecode(readProjectFile('android/app/google-services.json'))
              as Map<String, dynamic>;
      final androidClient =
          (googleServices['client'] as List<dynamic>).first
              as Map<String, dynamic>;
      final androidInfo = androidClient['client_info'] as Map<String, dynamic>;
      final androidPackage =
          androidInfo['android_client_info'] as Map<String, dynamic>;
      final iosPlist = readProjectFile('ios/Runner/GoogleService-Info.plist');

      expect(androidPackage['package_name'], 'magic.crm');
      expect(iosPlist, contains('<key>BUNDLE_ID</key>'));
      expect(iosPlist, contains('<string>magic.crm</string>'));
    });

    test('Supabase Auth uses the canonical project host for OAuth', () {
      final env = readProjectFile('lib/core/constants/env.dart');

      expect(env, contains('https://xblpnywnlhfgofskbdxb.supabase.co'));
      expect(env, isNot(contains('workers.dev')));
    });

    test('store legal artifacts include privacy, terms, and deletion URLs', () {
      final privacy = readProjectFile('release-site/privacy/index.html');
      final terms = readProjectFile('release-site/terms/index.html');
      final deletion = readProjectFile(
        'release-site/account-deletion/index.html',
      );
      final playStatus = readProjectFile(
        'docs/release/google_play_console_status.md',
      );

      expect(privacy, contains('Политика конфиденциальности'));
      expect(terms, contains('Условия использования'));
      expect(deletion, contains('Удаление аккаунта'));
      expect(
        playStatus,
        contains('https://magicmusiccrm-legal.vercel.app/privacy/'),
      );
      expect(
        playStatus,
        contains('https://magicmusiccrm-legal.vercel.app/account-deletion/'),
      );
    });

    test('Supabase hardening artifacts protect chat media and push dispatch', () {
      final migration = readProjectFile(
        'supabase/migrations/20260530122954_v2_storage_fcm_notification_hardening.sql',
      );
      final function = readProjectFile(
        'supabase/functions/send-notification/index.ts',
      );

      expect(migration, contains("set public = false"));
      expect(migration, contains("where id = 'chat-attachments'"));
      expect(migration, contains('notification_dispatch_secret'));
      expect(function, contains('NOTIFICATION_DISPATCH_SECRET'));
      expect(function, contains('FIREBASE_SERVICE_ACCOUNT'));
      expect(function, contains('.from("fcm_tokens")'));
      expect(function, isNot(contains('serviceAccount.json')));
    });
  });
}
