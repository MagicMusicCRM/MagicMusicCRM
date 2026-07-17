import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/update/windows_update_service.dart';

void main() {
  group('UpdateManifest.fromJson', () {
    test('parses a full manifest', () {
      final m = UpdateManifest.fromJson({
        'buildNumber': 142,
        'version': '1.2.1+142',
        'url': 'https://api.magicmusiccrm.ru/downloads/app.zip',
        'sha256': 'ABC123',
        'notes': 'Исправления',
      });
      expect(m.buildNumber, 142);
      expect(m.version, '1.2.1+142');
      expect(m.url, 'https://api.magicmusiccrm.ru/downloads/app.zip');
      expect(m.sha256, 'ABC123');
      expect(m.notes, 'Исправления');
    });

    test('blank sha256 becomes null', () {
      final m = UpdateManifest.fromJson({
        'buildNumber': 1,
        'version': 'x',
        'url': 'u',
        'sha256': '   ',
      });
      expect(m.sha256, isNull);
    });
  });

  group('shouldOfferUpdate', () {
    UpdateManifest man(int build, {String url = 'https://x/app.zip'}) =>
        UpdateManifest(buildNumber: build, version: '', url: url);

    test('offers when manifest build is higher', () {
      expect(shouldOfferUpdate(141, man(142)), isTrue);
    });
    test('does not offer for same build', () {
      expect(shouldOfferUpdate(142, man(142)), isFalse);
    });
    test('does not offer for older build (rollback protection)', () {
      expect(shouldOfferUpdate(142, man(141)), isFalse);
    });
    test('does not offer a newer build with no download url', () {
      expect(shouldOfferUpdate(141, man(142, url: '')), isFalse);
    });
    test('null manifest never offers', () {
      expect(shouldOfferUpdate(141, null), isFalse);
    });
  });
}
