import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/auth/presentation/widgets/auth_form_controls.dart';

Widget _testApp(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('AuthField preserves validation, suffix and disabled state', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController(text: 'bad');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _testApp(
        Form(
          key: formKey,
          child: AuthField(
            controller: controller,
            label: 'Почта',
            enabled: false,
            suffix: const Icon(Icons.mail_outline),
            validator: (value) => value == 'ok' ? null : 'Ошибка',
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();

    expect(find.text('Почта'), findsOneWidget);
    expect(find.byIcon(Icons.mail_outline), findsOneWidget);
    expect(find.text('Ошибка'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      isFalse,
    );
  });

  testWidgets('AuthField preserves input options and submit callback', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? submitted;

    await tester.pumpWidget(
      _testApp(
        AuthField(
          controller: controller,
          label: 'Код',
          hint: '123456',
          obscureText: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (value) => submitted = value,
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
    expect(field.keyboardType, TextInputType.number);
    expect(field.textInputAction, TextInputAction.done);
    expect(field.autocorrect, isFalse);
    expect(field.autofillHints, const [AutofillHints.oneTimeCode]);
    expect(field.inputFormatters, hasLength(1));
    expect(field.decoration?.hintText, '123456');

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '123456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, '123456');
  });

  testWidgets('AuthPrimaryButton submits only while enabled', (tester) async {
    var submitCount = 0;

    await tester.pumpWidget(
      _testApp(
        Column(
          children: [
            AuthPrimaryButton(
              label: 'Отправить',
              icon: Icons.send_outlined,
              height: 48,
              onPressed: () => submitCount += 1,
            ),
            const AuthPrimaryButton(label: 'Недоступно', onPressed: null),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Отправить'));
    await tester.tap(find.text('Недоступно'));

    expect(submitCount, 1);
    expect(find.byIcon(Icons.send_outlined), findsOneWidget);
    expect(tester.getSize(find.text('Отправить')).height, greaterThan(0));
    expect(
      tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((item) => item.opacity),
      [1.0, 0.42],
    );
  });
}
