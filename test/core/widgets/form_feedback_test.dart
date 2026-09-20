import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/form_feedback.dart';

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'submit reveals and focuses the first invalid field at $scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(900, 600);
        addTearDown(tester.view.reset);
        final form = GlobalKey<FormState>();
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        var saved = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.production,
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(900, 600),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Form(
                  key: form,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: Column(
                      children: [
                        TextFormField(
                          key: const Key('reason'),
                          decoration: const InputDecoration(
                            labelText: 'Причина изменения',
                          ),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Укажите причину'
                              : null,
                        ),
                        const SizedBox(height: 1200),
                      ],
                    ),
                  ),
                ),
                bottomNavigationBar: FilledButton(
                  onPressed: () {
                    saved = validateAndRevealForm(form);
                  },
                  child: const Text('Сохранить'),
                ),
              ),
            ),
          ),
        );
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(saved, isFalse);
        expect(find.text('Укажите причину'), findsOneWidget);
        expect(
          tester.getRect(find.byKey(const Key('reason'))).top,
          greaterThanOrEqualTo(0),
        );
        expect(
          tester.getRect(find.text('Укажите причину')).bottom,
          lessThan(600),
        );
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue,
        );
        final decoration = tester.widget<InputDecorator>(
          find.byType(InputDecorator),
        );
        expect(decoration.decoration.errorText, 'Укажите причину');
        await tester.enterText(
          find.byKey(const Key('reason')),
          'Просьба ученика',
        );
        await tester.pumpAndSettle();
        expect(find.text('Укажите причину'), findsNothing);
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(saved, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
