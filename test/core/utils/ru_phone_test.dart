import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/utils/ru_phone.dart';

void main() {
  group('nationalDigits', () {
    test('drops country code variants and keeps 10 national digits', () {
      expect(nationalDigits('+7 (909) 123-45-67'), '9091234567');
      expect(nationalDigits('89091234567'), '9091234567');
      expect(nationalDigits('79091234567'), '9091234567');
      expect(nationalDigits('9091234567'), '9091234567');
    });
    test('keeps partial input untouched (no padding/guessing)', () {
      expect(nationalDigits('909123'), '909123');
      expect(nationalDigits(''), '');
    });
    test('never returns more than 10 digits', () {
      expect(nationalDigits('890912345670000').length <= 10, isTrue);
    });
  });

  group('digitsToCanonical', () {
    test('emits +7XXXXXXXXXX only when 10 national digits present', () {
      expect(digitsToCanonical('+7 (909) 123 45 67'), '+79091234567');
      expect(digitsToCanonical('89091234567'), '+79091234567');
    });
    test('returns empty for partial/empty', () {
      expect(digitsToCanonical('909123'), '');
      expect(digitsToCanonical(''), '');
    });
  });

  group('canonicalToDisplay', () {
    test('renders full canonical as the RU mask', () {
      expect(canonicalToDisplay('+79091234567'), '+7 (909) 123 45 67');
    });
    test('renders partials by group, no trailing separators added blindly', () {
      expect(canonicalToDisplay('909'), '+7 (909');
      expect(canonicalToDisplay('90912'), '+7 (909) 12');
      expect(canonicalToDisplay(''), '');
    });
  });

  group('RuPhoneTextInputFormatter', () {
    final f = RuPhoneTextInputFormatter();
    TextEditingValue v(String t) => TextEditingValue(text: t);

    test('masks raw digits as the user types', () {
      final out = f.formatEditUpdate(v(''), v('9091234567'));
      expect(out.text, '+7 (909) 123 45 67');
      expect(out.selection.baseOffset, out.text.length); // caret at end
    });
    test('normalizes a pasted 8XXXXXXXXXX', () {
      final out = f.formatEditUpdate(v(''), v('89091234567'));
      expect(out.text, '+7 (909) 123 45 67');
    });
    test('partial entry shows partial mask', () {
      final out = f.formatEditUpdate(v(''), v('909'));
      expect(out.text, '+7 (909');
    });
  });
}
