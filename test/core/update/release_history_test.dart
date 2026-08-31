import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/update/release_history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled history contains every published release', () async {
    final raw = await rootBundle.loadString(releaseHistoryAssetPath);
    final releases = parseReleaseHistory(raw);

    expect(releases.first.version, '1.5.28+208');
    expect(releases.first.buildNumber, 208);
    expect(releases, hasLength(48));
    expect(releases.last.version, '1.0.0');
    expect(
      releases.map((release) => release.buildNumber),
      containsAll(<int>[
        180,
        181,
        182,
        183,
        184,
        187,
        188,
        189,
        190,
        191,
        192,
        193,
        194,
        195,
        196,
        197,
        198,
        199,
        200,
        201,
        202,
        203,
        204,
        205,
        206,
        207,
        208,
      ]),
    );
    expect(raw, isNot(contains('—')));
    for (final release in releases) {
      final userText = <String>[
        release.date,
        release.title,
        release.summary,
        ...release.changes,
      ].join(' ');
      expect(RegExp(r'[A-Za-z]').hasMatch(userText), isFalse);
    }
  });

  test('installed build resolves to its exact release', () async {
    final version = await loadInstalledAppVersion(currentBuild: 191);

    expect(version.version, '1.5.11+191');
    expect(version.shortVersion, '1.5.11');
  });

  test('release package metadata matches the newest history entry', () async {
    final raw = await rootBundle.loadString(releaseHistoryAssetPath);
    final latest = parseReleaseHistory(raw).first;
    final dottedVersion = latest.version.replaceFirst('+', '.');
    final dashedVersion = latest.version.replaceFirst('+', '-');
    final pubspec = await File('pubspec.yaml').readAsString();
    final installer = await File('windows_installer.iss').readAsString();

    expect(pubspec, contains('version: ${latest.version}'));
    expect(pubspec, contains('msix_version: $dottedVersion'));
    expect(installer, contains('AppVersion=$dottedVersion'));
    expect(
      installer,
      contains('OutputBaseFilename=MagicMusicCRM-$dashedVersion-Setup'),
    );
  });

  test('history endpoint accepts only the production HTTPS location', () {
    expect(
      isTrustedReleaseHistoryEndpoint(
        'https://api.magicmusiccrm.ru/downloads/release-history.json',
      ),
      isTrue,
    );
    expect(
      isTrustedReleaseHistoryEndpoint(
        'http://api.magicmusiccrm.ru/downloads/release-history.json',
      ),
      isFalse,
    );
    expect(
      isTrustedReleaseHistoryEndpoint(
        'https://evil.example/downloads/release-history.json',
      ),
      isFalse,
    );
  });

  test('parser rejects duplicate or unordered builds', () {
    const duplicate = '''
      {"releases":[
        {"version":"2","buildNumber":2,"date":"сегодня","title":"Новая","summary":"Описание","changes":["Правка"]},
        {"version":"2","buildNumber":2,"date":"вчера","title":"Старая","summary":"Описание","changes":["Правка"]}
      ]}
    ''';

    expect(() => parseReleaseHistory(duplicate), throwsFormatException);
  });
}
