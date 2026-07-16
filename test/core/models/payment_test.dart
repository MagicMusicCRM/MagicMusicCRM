import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/payment.dart';

void main() {
  group('Payment.fromMap (M2 real DTO parse)', () {
    test('parses a numeric-string amount and keeps the raw value', () {
      final p = Payment.fromMap({'amount': '1500.50', 'currency': 'RUB'});
      expect(p.amount, 1500.50);
      expect(p.amountRaw, '1500.50');
      expect(p.currency, 'RUB');
    });

    test('accepts a numeric amount and defaults to 0 when absent/garbage', () {
      expect(Payment.fromMap({'amount': 200}).amount, 200);
      expect(Payment.fromMap({'amount': 'n/a'}).amount, 0);
      expect(Payment.fromMap(<String, dynamic>{}).amount, 0);
    });

    test('methodLabel falls back method -> type -> empty', () {
      expect(Payment.fromMap({'method': 'card'}).methodLabel, 'card');
      expect(Payment.fromMap({'type': 'cash'}).methodLabel, 'cash');
      expect(Payment.fromMap(<String, dynamic>{}).methodLabel, '');
    });

    test('note falls back notes -> description -> empty', () {
      expect(Payment.fromMap({'notes': 'paid'}).note, 'paid');
      expect(Payment.fromMap({'description': 'refund'}).note, 'refund');
      expect(Payment.fromMap(<String, dynamic>{}).note, '');
    });

    test('reads the nested student and builds the display name', () {
      final p = Payment.fromMap({
        'id': 'pay-1',
        'student_id': 'stu-1',
        'students': {
          'id': 'stu-entity',
          'first_name': 'Анна',
          'last_name': 'Иванова',
        },
      });
      expect(p.hasStudent, isTrue);
      expect(p.studentEntityId, 'stu-entity');
      expect(p.studentName, 'Анна Иванова');
    });

    test('has no student when the nested map is absent', () {
      final p = Payment.fromMap({'id': 'pay-2'});
      expect(p.hasStudent, isFalse);
      expect(p.studentName, '');
      expect(p.studentEntityId, isNull);
    });
  });
}
