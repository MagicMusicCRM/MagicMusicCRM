import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/utils/ru_phone.dart';

void main() {
  group('isCanonicalRu', () {
    test('returns true for a valid +7 number', () {
      expect(isCanonicalRu('+79991234567'), isTrue);
    });

    test('returns true for another valid +7 number', () {
      expect(isCanonicalRu('+70001112233'), isTrue);
    });

    test('returns false for null', () {
      expect(isCanonicalRu(null), isFalse);
    });

    test('returns false for empty string', () {
      expect(isCanonicalRu(''), isFalse);
    });

    test('returns false for partial number', () {
      expect(isCanonicalRu('+7999'), isFalse);
    });

    test('returns false for 11-digit national part', () {
      expect(isCanonicalRu('+799912345678'), isFalse);
    });

    test('returns false for non-+7 international number', () {
      expect(isCanonicalRu('+12025550123'), isFalse);
    });

    test('returns false for bare digits without +7', () {
      expect(isCanonicalRu('79991234567'), isFalse);
    });

    test('returns false for short unformatted number', () {
      expect(isCanonicalRu('12345'), isFalse);
    });
  });

  group('international flag derivation for profile screen', () {
    // The profile screen passes international: false (the default) always.
    // This group asserts the chosen rule:
    //   international = phone.isNotEmpty && !isCanonicalRu(phone)
    // so that empty and canonical values open RU-masked mode,
    // while a stored non-canonical value opens international mode.

    bool internationalFlag(String phone) =>
        phone.isNotEmpty && !isCanonicalRu(phone);

    test('empty phone → RU mode (international = false)', () {
      expect(internationalFlag(''), isFalse);
    });

    test('canonical +7 phone → RU mode (international = false)', () {
      expect(internationalFlag('+79991234567'), isFalse);
    });

    test('stored non-canonical phone → international mode (international = true)', () {
      expect(internationalFlag('+12025550123'), isTrue);
    });

    test('garbage value → international mode', () {
      expect(internationalFlag('not-a-phone'), isTrue);
    });
  });

  group('digitsToCanonical', () {
    test('10 national digits from raw produce canonical', () {
      expect(digitsToCanonical('9991234567'), equals('+79991234567'));
    });

    test('strips leading 7 trunk prefix', () {
      expect(digitsToCanonical('79991234567'), equals('+79991234567'));
    });

    test('strips leading 8 trunk prefix', () {
      expect(digitsToCanonical('89991234567'), equals('+79991234567'));
    });

    test('returns empty for fewer than 10 national digits', () {
      expect(digitsToCanonical('999123'), equals(''));
    });
  });
}
