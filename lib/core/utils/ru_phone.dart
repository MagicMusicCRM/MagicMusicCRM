import 'package:flutter/services.dart';

/// All digit characters of [raw], in order.
String digitsFrom(String raw) => raw.replaceAll(RegExp(r'\D'), '');

/// Up to 10 Russian national digits (country code 7/8 stripped, never padded).
String nationalDigits(String raw) {
  var d = digitsFrom(raw);
  if (d.length == 11 && (d.startsWith('7') || d.startsWith('8'))) {
    d = d.substring(1);
  }
  if (d.length > 10) d = d.substring(d.length - 10);
  return d;
}

/// `+7XXXXXXXXXX` only when 10 national digits are present, else `''`.
String digitsToCanonical(String raw) {
  final d = nationalDigits(raw);
  return d.length == 10 ? '+7$d' : '';
}

/// Renders [raw] (canonical or partial) as `+7 (XXX) XXX XX XX`,
/// filling only the groups for which digits exist.
String canonicalToDisplay(String raw) {
  final d = nationalDigits(raw);
  if (d.isEmpty) return '';
  final b = StringBuffer('+7 (');
  b.write(d.substring(0, d.length < 3 ? d.length : 3));
  if (d.length > 3) b.write(')');
  if (d.length > 3) b.write(' ${d.substring(3, d.length < 6 ? d.length : 6)}');
  if (d.length > 6) b.write(' ${d.substring(6, d.length < 8 ? d.length : 8)}');
  if (d.length > 8) b.write(' ${d.substring(8, d.length < 10 ? d.length : 10)}');
  return b.toString();
}

/// Re-masks the input on every edit and pins the caret to the end
/// (simple, predictable for a fixed-format field).
class RuPhoneTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final masked = canonicalToDisplay(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}
