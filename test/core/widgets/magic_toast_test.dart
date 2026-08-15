import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_toast.dart';

/// #16 «тосты не исчезают»: MagicToast owns its dismissal [Timer], so it must
/// auto-dismiss regardless of Flutter 3.41's SnackBar `persist` semantics —
/// including with an undo action attached. Danger toasts additionally get a
/// manual dismiss affordance.
void main() {
  Widget host({required void Function(BuildContext) onShow}) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => onShow(context),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );

  testWidgets('undo toast (with action) auto-dismisses in ~3 s', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onShow: (context) => MagicToast.show(
          context,
          'Занятие перенесено',
          actionLabel: 'Отменить',
          onAction: () {},
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('Занятие перенесено'), findsOneWidget);
    expect(find.text('Отменить'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Занятие перенесено'), findsNothing);
  });

  testWidgets('success toast auto-dismisses in ~3 s', (tester) async {
    await tester.pumpWidget(
      host(
        onShow: (context) => MagicToast.show(
          context,
          'Занятие отменено',
          type: MagicToastType.success,
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('Занятие отменено'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Занятие отменено'), findsNothing);
  });

  testWidgets('danger toast is tap-to-dismiss and still auto-dismisses', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onShow: (context) => MagicToast.show(
          context,
          'Не удалось подготовить форму задачи',
          type: MagicToastType.danger,
        ),
      ),
    );

    // Tap the ✕ — dismissed immediately.
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('Не удалось подготовить форму задачи'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось подготовить форму задачи'), findsNothing);

    // Untouched — auto-dismisses on the same three-second product budget.
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('Не удалось подготовить форму задачи'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось подготовить форму задачи'), findsNothing);
  });

  testWidgets('action tap runs the callback and dismisses', (tester) async {
    var undone = false;
    await tester.pumpWidget(
      host(
        onShow: (context) => MagicToast.show(
          context,
          'Лид конвертирован в ученика',
          actionLabel: 'Отменить',
          onAction: () => undone = true,
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();

    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
    expect(find.text('Лид конвертирован в ученика'), findsNothing);
  });

  testWidgets('danger toast does not expose technical English text', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onShow: (context) => MagicToast.show(
          context,
          'Schedule Analyzer failed: PostgreSQL constraint',
          detail: 'SocketException: connection reset',
          type: MagicToastType.danger,
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.text('Не удалось выполнить действие.'), findsOneWidget);
    expect(find.text('Попробуйте снова.'), findsOneWidget);
    expect(find.textContaining('Schedule Analyzer'), findsNothing);
    expect(find.textContaining('SocketException'), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
