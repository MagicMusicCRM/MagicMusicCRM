import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/utils/ru_phone.dart';

void main() {
  group('nationalDigits', () {
    test('does not double-count the +7 prefix at partial lengths', () {
      expect(nationalDigits('+7 (9'), '9');        // was '79' (bug)
      expect(nationalDigits('+7 (495) 12'), '49512');
    });
    test('clears to empty when only the prefix remains (deletion works)', () {
      expect(nationalDigits('+7 ('), '');          // was '7' (bug: stuck)
      expect(nationalDigits('+7'), '');
      expect(nationalDigits(''), '');
    });
    test('strips a leading 7 or 8 country code', () {
      expect(nationalDigits('+79991234567'), '9991234567');
      expect(nationalDigits('89991234567'), '9991234567');
      expect(nationalDigits('79991234567'), '9991234567');
    });
    test('keeps a full national number that does not start with 7/8', () {
      expect(nationalDigits('4951234567'), '4951234567');
    });
  });

  group('canonicalToDisplay / digitsToCanonical', () {
    test('formats a full canonical number', () {
      expect(canonicalToDisplay('+79991234567'), '+7 (999) 123 45 67');
    });
    test('emits canonical only when 10 national digits present', () {
      expect(digitsToCanonical('+7 (999) 123 45 67'), '+79991234567');
      expect(digitsToCanonical('+7 ('), '');
    });
  });

  group('RuPhoneTextInputFormatter (deletion)', () {
    test('backspace past the last digit re-masks to empty, not +7 (7', () {
      final f = RuPhoneTextInputFormatter();
      // user had '+7 (9', presses backspace -> Flutter proposes '+7 ('
      final out = f.formatEditUpdate(
        const TextEditingValue(text: '+7 (9'),
        const TextEditingValue(text: '+7 ('),
      );
      expect(out.text, '');
    });
  });
}
