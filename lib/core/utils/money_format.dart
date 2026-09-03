/// Russian UI money format: exact minor units, grouped digits and two decimals.
String formatPaymentMinor(BigInt minor, {String currencyCode = 'RUB'}) {
  final absolute = minor.abs();
  final whole = (absolute ~/ BigInt.from(100)).toString();
  final fraction = (absolute % BigInt.from(100)).toString().padLeft(2, '0');
  final grouped = whole.replaceAllMapped(
    RegExp(r'(?<=\d)(?=(\d{3})+$)'),
    (_) => '\u00a0',
  );
  final currency = currencyCode == 'RUB' ? '₽' : currencyCode;
  return '${minor.isNegative ? '−' : ''}$grouped,$fraction $currency';
}

/// Presentation bridge for legacy API amounts expressed in major units.
/// Decimal strings stay exact; this is not the parser used by payment forms.
String formatPaymentMajor(Object? amount, {String currencyCode = 'RUB'}) {
  final match = RegExp(
    r'^([+-]?)(\d+)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$',
  ).firstMatch(amount?.toString() ?? '');
  if (match == null) return '—';
  final fraction = match[3] ?? '';
  final digits = BigInt.parse('${match[2]}$fraction');
  final scale = 2 + int.parse(match[4] ?? '0') - fraction.length;
  final power = BigInt.from(10).pow(scale.abs());
  final minor = scale >= 0
      ? digits * power
      : (digits + power ~/ BigInt.two) ~/ power;
  return formatPaymentMinor(
    match[1] == '-' ? -minor : minor,
    currencyCode: currencyCode,
  );
}
