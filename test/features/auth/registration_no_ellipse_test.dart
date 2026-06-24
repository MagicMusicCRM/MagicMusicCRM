import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/registration_screen.dart';

void main() {
  testWidgets('registration screen has no RadialGradient glow', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: RegistrationScreen()),
    ));
    expect(
      find.byWidgetPredicate((w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient is RadialGradient),
      findsNothing,
    );
  });
}
