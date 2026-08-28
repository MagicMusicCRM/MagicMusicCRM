import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/update/release_history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled history contains every published release', () async {
    final raw = await rootBundle.loadString(releaseHistoryAssetPath);
    final releases = parseReleaseHistory(raw);

    expect(releases.first.version, '1.5.18+198');
    expect(releases.first.buildNumber, 198);
    expect(releases, hasLength(38));
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
