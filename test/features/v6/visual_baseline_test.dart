import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_page_state.dart';

void main() {
  test('Inter and motion tokens are bundled and canonical', () {
    expect(File('assets/fonts/InterVariable.ttf').lengthSync(), greaterThan(0));
    expect(
      File('assets/fonts/InterVariable-Italic.ttf').lengthSync(),
      greaterThan(0),
    );
    expect(AppTheme.dark.textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(AppTheme.dark.brightness, Brightness.dark);
    expect(AppMotion.fast, const Duration(milliseconds: 160));
    expect(AppMotion.medium, const Duration(milliseconds: 240));
    expect(AppMotion.slow, const Duration(milliseconds: 300));
  });

  for (final width in [360.0, 600.0, 839.0, 840.0, 1000.0, 1200.0]) {
    testWidgets('critical state fits width ${width.toInt()} at 200% text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: MagicPageState(
              kind: MagicPageStateKind.error,
              title: 'Не удалось загрузить общешкольные настройки',
              message: 'Проверьте подключение и повторите безопасную загрузку.',
              actionLabel: 'Повторить загрузку',
              onAction: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Повторить загрузку'), findsOneWidget);
    });
  }

  testWidgets('reduced motion resolves token duration to zero', (tester) async {
    Duration? effective;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              effective = AppMotion.effective(context, AppMotion.slow);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(effective, Duration.zero);
  });
}
