import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';

void main() {
  testWidgets('keeps label and empty mask with a custom decoration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RuPhoneField(
            labelText: 'Номер телефона',
            decoration: const InputDecoration(filled: true),
            onCanonicalChanged: (_) {},
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.labelText, 'Номер телефона');
    expect(field.decoration?.hintText, '+7 (___) ___ __ __');
  });

  testWidgets('types digits → shows mask + emits canonical', (tester) async {
    String? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RuPhoneField(onCanonicalChanged: (c) => captured = c),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '9091234567');
    await tester.pump();

    expect(find.text('+7 (909) 123 45 67'), findsOneWidget);
    expect(captured, '+79091234567');
  });

  testWidgets('partial input emits empty canonical', (tester) async {
    String? captured = 'sentinel';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RuPhoneField(onCanonicalChanged: (c) => captured = c),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '909');
    await tester.pump();
    expect(captured, '');
  });

  testWidgets('seeds masked display from initialCanonical', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RuPhoneField(
            initialCanonical: '+79091234567',
            onCanonicalChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('+7 (909) 123 45 67'), findsOneWidget);
  });

  testWidgets('international mode: emits raw value, no +7 mask applied', (
    tester,
  ) async {
    String? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RuPhoneField(
            international: true,
            onCanonicalChanged: (c) => captured = c,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '+1 202 555 0123');
    await tester.pump();

    // Raw value is emitted (not a +7 canonical).
    expect(captured, '+1 202 555 0123');
    // No +7 ( mask should appear.
    expect(find.textContaining('+7 ('), findsNothing);
  });
}
