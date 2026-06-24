import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/registration_screen.dart';

void main() {
  group('RegistrationScreen phone field', () {
    testWidgets('(a) RuPhoneField is present in the registration screen',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: RegistrationScreen()),
      ));
      expect(find.byType(RuPhoneField), findsOneWidget);
    });

    testWidgets(
        '(b) tapping register with empty phone shows phone error message',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: RegistrationScreen()),
      ));

      // Fill in all required TextFormFields so the Form validation passes.
      // Field order in the Column: name (index 0), email (1), password (2),
      // confirm-password (3).  The phone widget is a plain TextField inside
      // RuPhoneField (not a TextFormField), so it doesn't affect the indices.

      // Fill name
      await tester.enterText(find.byType(TextFormField).at(0), 'Test User');
      // Fill email
      await tester.enterText(
          find.byType(TextFormField).at(1), 'test@example.com');
      // Fill password
      await tester.enterText(
          find.byType(TextFormField).at(2), 'password123');
      // Fill confirm password
      await tester.enterText(
          find.byType(TextFormField).at(3), 'password123');

      // Do NOT enter a phone number — _canonicalPhone stays ''.

      // Scroll until the register button is visible and tap it.
      final registerButton = find.text('Зарегистрироваться');
      await tester.ensureVisible(registerButton);
      await tester.pump();
      await tester.tap(registerButton);
      await tester.pump();

      // The phone-empty guard calls _showError, which sets _errorMessage,
      // rendering _AuthErrorPill with the message.
      expect(
        find.text('Введите корректный номер телефона в формате +7…'),
        findsOneWidget,
      );
    });
  });
}
