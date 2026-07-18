import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/auto_dismiss_scaffold_messenger.dart';

/// #16 root-cause regression: Flutter 3.41 defaults SnackBar to
/// `persist = action != null`, making every «…/Отменить» snackbar immortal and
/// queueing all later toasts behind it. [AutoDismissScaffoldMessenger] (mounted
/// app-wide via MaterialApp.builder in main.dart) must neutralise that default
/// at the source, without touching the ~100 call sites.
void main() {
  Widget host(SnackBar snackBar) => MaterialApp(
    builder: (context, child) =>
        AutoDismissScaffoldMessenger(child: child ?? const SizedBox.shrink()),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).showSnackBar(snackBar),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );

  testWidgets('snackbar WITH an action auto-dismisses after its duration '
      '(the «Занятие перенесено»/«Отменить» shape)', (tester) async {
    await tester.pumpWidget(
      host(
        SnackBar(
          content: const Text('Занятие перенесено'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(label: 'Отменить', onPressed: () {}),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Занятие перенесено'), findsOneWidget);

    // Well past duration + transitions: with the raw framework default this
    // stayed visible forever (verified empirically on this SDK).
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Занятие перенесено'), findsNothing);
  });

  testWidgets(
    'queued actionless snackbar is not starved behind an action one',
    (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AutoDismissScaffoldMessenger(
            child: child ?? const SizedBox.shrink(),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final messenger = ScaffoldMessenger.of(ctx);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Занятие перенесено'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(label: 'Отменить', onPressed: () {}),
        ),
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Занятие отменено'),
          duration: Duration(seconds: 3),
        ),
      );
      await tester.pump();
      // Complete the entrance animation; ScaffoldMessenger starts the duration
      // timer only after the snackbar is fully visible.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Занятие перенесено'), findsOneWidget);

      // First one leaves on time, the queued one gets its turn and also leaves.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Занятие перенесено'), findsNothing);
      expect(find.text('Занятие отменено'), findsOneWidget);
      // Complete the queued snackbar's own entrance before measuring its timer.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Занятие отменено'), findsNothing);
    },
  );

  group('withSnackBarAutoDismiss', () {
    test('strips persist only from action snackbars', () {
      final withAction = SnackBar(
        content: const Text('x'),
        action: SnackBarAction(label: 'y', onPressed: () {}),
      );
      expect(withAction.persist, isTrue, reason: 'framework 3.41 default');
      expect(withSnackBarAutoDismiss(withAction).persist, isFalse);
      expect(withSnackBarAutoDismiss(withAction).action, isNotNull);
    });

    test('keeps an explicitly persistent actionless snackbar untouched', () {
      const explicit = SnackBar(content: Text('x'), persist: true);
      expect(identical(withSnackBarAutoDismiss(explicit), explicit), isTrue);
    });

    test('passes plain snackbars through unchanged', () {
      const plain = SnackBar(content: Text('x'));
      final rebuilt = withSnackBarAutoDismiss(plain);
      expect(identical(rebuilt, plain), isFalse);
      expect(rebuilt.duration, const Duration(seconds: 3));
    });

    test('preserves the visual/behavioural fields it copies', () {
      final original = SnackBar(
        content: const Text('x'),
        backgroundColor: const Color(0xFF112233),
        duration: const Duration(seconds: 7),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        action: SnackBarAction(label: 'y', onPressed: () {}),
      );
      final rebuilt = withSnackBarAutoDismiss(original);
      expect(rebuilt.backgroundColor, const Color(0xFF112233));
      expect(rebuilt.duration, const Duration(seconds: 3));
      expect(rebuilt.behavior, SnackBarBehavior.floating);
      expect(rebuilt.showCloseIcon, isTrue);
      expect(rebuilt.action, same(original.action));
    });
  });
}
