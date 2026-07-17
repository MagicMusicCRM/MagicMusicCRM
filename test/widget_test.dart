import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readProjectFile(String path) => File(path).readAsStringSync();

void main() {
  group('release config', () {
    test('Android identity and release guard are configured', () {
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
    });

    test('runtime uses v3 backend without legacy auth/storage SDKs', () {
      final env = readProjectFile('lib/core/constants/env.dart');
      final main = readProjectFile('lib/main.dart');
      final pubspec = readProjectFile('pubspec.yaml');

      // Domain moved 2026-07-10: phantom-net.ru was lost, magicmusiccrm.ru is
      // the permanent one (see the note in env.dart). The guard is "the app
      // points at OUR backend by default", so it tracks the current domain.
      expect(env, contains('https://api.magicmusiccrm.ru/api'));
      expect(env, isNot(contains("defaultValue: 'https://api.phantom-net.ru")));
      expect(pubspec, isNot(contains('supabase_flutter:')));
      expect(pubspec, isNot(contains('google_sign_in:')));
      expect(pubspec, isNot(contains('app_links:')));
      expect(pubspec, isNot(contains('google_fonts:')));
      expect(pubspec, isNot(contains('cupertino_icons:')));
      expect(main, isNot(contains('Supabase.initialize')));
    });

    test('Firebase mobile package ids match the app id', () {
      final googleServices =
          jsonDecode(readProjectFile('android/app/google-services.json'))
              as Map<String, dynamic>;
      final clients = (googleServices['client'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final androidPackages = clients.map((client) {
        final clientInfo = client['client_info'] as Map<String, dynamic>;
        final androidInfo =
            clientInfo['android_client_info'] as Map<String, dynamic>;
        return androidInfo['package_name'];
      });
      final iosPlist = readProjectFile('ios/Runner/GoogleService-Info.plist');

      expect(androidPackages, contains('magic.crm'));
      expect(iosPlist, contains('<key>BUNDLE_ID</key>'));
      expect(iosPlist, contains('<string>magic.crm</string>'));
    });

    test('integration smoke is wired without local secrets', () {
      final pubspec = readProjectFile('pubspec.yaml');
      final smoke = readProjectFile(
        'integration_test/app_launch_smoke_test.dart',
      );

      expect(pubspec, contains('integration_test:'));
      expect(
        smoke,
        contains('IntegrationTestWidgetsFlutterBinding.ensureInitialized'),
      );
      expect(smoke, contains('MemoryMagicTokenStore()'));
      expect(smoke, contains('_NoopNotificationService'));
      expect(smoke, contains('_accountDeletionSmokeRouter'));
      expect(smoke, isNot(contains('HOLLIHOP_AUTH_KEY')));
      expect(smoke, isNot(contains('MIGRATION_DATABASE_URL')));
    });

    test('Android launch theme matches the Flutter boot gate', () {
      final colors = readProjectFile(
        'android/app/src/main/res/values/colors.xml',
      );
      final launchBackground = readProjectFile(
        'android/app/src/main/res/drawable/launch_background.xml',
      );
      final launchBackgroundV21 = readProjectFile(
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      );
      final styles = readProjectFile(
        'android/app/src/main/res/values/styles.xml',
      );
      final stylesV31 = readProjectFile(
        'android/app/src/main/res/values-v31/styles.xml',
      );
      final nightStylesV31 = readProjectFile(
        'android/app/src/main/res/values-night-v31/styles.xml',
      );
      final nightStyles = readProjectFile(
        'android/app/src/main/res/values-night/styles.xml',
      );

      expect(
        colors,
        contains('<color name="launch_background">#101114</color>'),
      );
      expect(colors, isNot(contains('#F7F3EA')));
      expect(launchBackground, isNot(contains('android:gravity="center"')));
      expect(launchBackground, isNot(contains('android:shape="oval"')));
      expect(launchBackgroundV21, isNot(contains('android:gravity="center"')));
      expect(launchBackgroundV21, isNot(contains('android:shape="oval"')));
      expect(styles, contains('@color/launch_background'));
      expect(stylesV31, contains('windowSplashScreenBackground'));
      expect(stylesV31, contains('@color/launch_background'));
      expect(
        stylesV31,
        contains(
          'android:windowSplashScreenAnimatedIcon">@drawable/launch_transparent_icon',
        ),
      );
      expect(stylesV31, isNot(contains('@mipmap/ic_launcher')));
      expect(
        stylesV31,
        isNot(contains('windowSplashScreenIconBackgroundColor')),
      );
      expect(
        nightStylesV31,
        contains(
          'android:windowSplashScreenAnimatedIcon">@drawable/launch_transparent_icon',
        ),
      );
      expect(nightStylesV31, isNot(contains('@mipmap/ic_launcher')));
      expect(
        nightStylesV31,
        isNot(contains('windowSplashScreenIconBackgroundColor')),
      );
      expect(nightStyles, isNot(contains('Theme.Black.NoTitleBar')));
    });
  });
}
