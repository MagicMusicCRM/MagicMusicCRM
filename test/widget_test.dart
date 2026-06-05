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
      final androidClient = (googleServices['client'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((client) {
            final clientInfo = client['client_info'] as Map<String, dynamic>;
            final androidInfo =
                clientInfo['android_client_info'] as Map<String, dynamic>;
            return androidInfo['package_name'] == 'magic.crm';
          });
      final androidInfo = androidClient['client_info'] as Map<String, dynamic>;
      final androidPackage =
          androidInfo['android_client_info'] as Map<String, dynamic>;
      final iosPlist = readProjectFile('ios/Runner/GoogleService-Info.plist');

      expect(androidPackage['package_name'], 'magic.crm');
      expect(
        androidClient['oauth_client'].toString(),
        contains('1038036512599-vg813c70pl4qjv7kmtse94mgkorfatg6'),
      );
      expect(iosPlist, contains('<key>BUNDLE_ID</key>'));
      expect(iosPlist, contains('<string>magic.crm</string>'));
    });

    test('Supabase Auth uses the custom project host for Auth', () {
      final env = readProjectFile('lib/core/constants/env.dart');

      expect(env, contains('https://api.magic-music.org'));
      expect(env, isNot(contains('workers.dev')));
    });

    test('email OTP UI is locked to 6 numeric digits', () {
      final otpScreen = readProjectFile(
        'lib/features/auth/presentation/screens/email_otp_screen.dart',
      );
      final loginScreen = readProjectFile(
        'lib/features/auth/presentation/screens/login_screen.dart',
      );

      expect(otpScreen, contains('const int emailOtpCodeLength = 6'));
      expect(otpScreen, contains('FilteringTextInputFormatter.digitsOnly'));
      expect(otpScreen, contains("hintText: '000000'"));
      expect(otpScreen, isNot(contains("hintText: '00000000'")));
      expect(loginScreen, isNot(contains('Войти без пароля по email-коду')));
      expect(loginScreen, isNot(contains('EmailOtpPurpose.passwordlessLogin')));
    });

    test('Google sign-in falls back to Supabase OAuth redirect', () {
      final authService = readProjectFile(
        'lib/features/auth/data/services/supa_auth_service.dart',
      );

      expect(authService, contains('_signInWithSupabaseGoogleOAuth'));
      expect(authService, contains('_shouldFallbackToSupabaseOAuth'));
      expect(authService, contains('redirectTo: Env.authRedirectUrl'));
      expect(authService, contains('OAuthProvider.google'));
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
