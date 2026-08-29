import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop login keeps one centered, contained auth surface', (
    tester,
  ) async {
    await _pumpLogin(tester, const Size(1280, 720));

    final card = find.byKey(const ValueKey('login-form-card'));
    expect(card, findsOneWidget);

    final cardRect = tester.getRect(card);
    expect(cardRect.center.dx, closeTo(640, 1));
    expect(cardRect.width, inInclusiveRange(380, 420));
    expect(cardRect.left, greaterThanOrEqualTo(24));
    expect(cardRect.right, lessThanOrEqualTo(1256));

    final backdrop = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('login-backdrop')),
    );
    final backdropDecoration = backdrop.decoration as BoxDecoration;
    expect(backdropDecoration.color, AppColor.sidebar);
    expect(backdropDecoration.gradient, isNull);

    final cardWidget = tester.widget<Container>(card);
    final cardDecoration = cardWidget.decoration! as BoxDecoration;
    expect(cardDecoration.color, AppColor.bg);

    final firstField = tester.widget<TextField>(find.byType(TextField).first);
    expect(firstField.decoration?.fillColor, AppColor.surface);

    final heading = find.byKey(const ValueKey('login-heading'));
    expect(heading, findsOneWidget);
    expect(
      tester.getRect(find.byType(Image)).right,
      lessThan(tester.getRect(find.text('Вход в систему')).left),
    );

    final createAccountRect = tester.getRect(find.text('Создать аккаунт'));
    expect(createAccountRect.top, greaterThanOrEqualTo(0));
    expect(createAccountRect.bottom, lessThanOrEqualTo(720));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone login remains centered without horizontal overflow', (
    tester,
  ) async {
    await _pumpLogin(tester, const Size(360, 640));

    final card = find.byKey(const ValueKey('login-form-card'));
    expect(card, findsOneWidget);

    final cardRect = tester.getRect(card);
    expect(cardRect.center.dx, closeTo(180, 1));
    expect(cardRect.left, greaterThanOrEqualTo(12));
    expect(cardRect.right, lessThanOrEqualTo(348));

    await tester.ensureVisible(find.text('Создать аккаунт'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpLogin(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(theme: AppTheme.production, home: const LoginScreen()),
    ),
  );
  await tester.pumpAndSettle();
}
