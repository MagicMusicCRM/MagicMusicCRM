import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/utils/money_format.dart';

void main() {
  test('minor amounts always use grouped digits and two decimals', () {
    expect(formatPaymentMinor(BigInt.from(123456)), '1\u00a0234,56 ₽');
    expect(formatPaymentMinor(BigInt.from(-123456)), '−1\u00a0234,56 ₽');
    expect(formatPaymentMinor(BigInt.zero), '0,00 ₽');
    expect(formatPaymentMinor(BigInt.from(123400)), '1\u00a0234,00 ₽');
    expect(formatPaymentMinor(BigInt.from(-1)), '−0,01 ₽');
    expect(
      formatPaymentMinor(BigInt.from(123456), currencyCode: 'EUR'),
      '1\u00a0234,56 EUR',
    );
  });

  test('keeps every digit beyond native integer and double precision', () {
    const major = '123456789012345678901234.56';
    const expected =
        '123\u00a0456\u00a0789\u00a0012\u00a0345\u00a0678\u00a0901\u00a0234,56 ₽';
    final minor = BigInt.parse('12345678901234567890123456');
    expect(formatPaymentMinor(minor), expected);
    expect(formatPaymentMinor(-minor), '−$expected');
    expect(formatPaymentMajor(major), expected);
    expect(formatPaymentMajor('-$major'), '−$expected');
  });

  test(
    'legacy decimal display matches minor display without changing input parsing',
    () {
      expect(
        formatPaymentMajor('1234.56'),
        formatPaymentMinor(BigInt.from(123456)),
      );
      expect(
        formatPaymentMajor(-1234.56),
        formatPaymentMinor(BigInt.from(-123456)),
      );
      expect(formatPaymentMajor('1.23456e3'), '1\u00a0234,56 ₽');
      expect(formatPaymentMajor('0.005'), '0,01 ₽');
      expect(formatPaymentMajor('-0.005'), '−0,01 ₽');
      expect(formatPaymentMajor(0.1 + 0.2), '0,30 ₽');
      expect(formatPaymentMajor('unknown'), '—');
    },
  );
}
