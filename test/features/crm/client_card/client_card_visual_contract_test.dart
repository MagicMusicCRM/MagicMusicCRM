import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_ui.dart';

void main() {
  test(
    'client card fields use one neutral surface and one control geometry',
    () {
      final decoration = clientCardInputDecoration(
        const ColorScheme.light(),
        label: 'Имя',
        isDense: true,
      );

      expect(decoration.filled, isTrue);
      expect(decoration.fillColor, AppColor.surface);
      expect(
        decoration.contentPadding,
        const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      );

      final enabled = decoration.enabledBorder! as OutlineInputBorder;
      final focused = decoration.focusedBorder! as OutlineInputBorder;
      expect(enabled.borderRadius, BorderRadius.circular(AppRadius.control));
      expect(enabled.borderSide.color, AppColor.borderSoft);
      expect(focused.borderRadius, BorderRadius.circular(AppRadius.control));
      expect(focused.borderSide.color, AppColor.brandSolid);
      expect(focused.borderSide.width, 1.5);
    },
  );

  test('client card picker overlay stays neutral with warm states', () {
    final theme = clientCardControlTheme(ThemeData.light());
    final dropdownTheme = theme.dropdownMenuTheme;

    expect(
      dropdownTheme.menuStyle!.backgroundColor!.resolve(<WidgetState>{}),
      AppColor.overlay,
    );
    expect(
      dropdownTheme.menuStyle!.surfaceTintColor!.resolve(<WidgetState>{}),
      Colors.transparent,
    );
    expect(
      theme.menuButtonTheme.style!.backgroundColor!.resolve(<WidgetState>{
        WidgetState.focused,
      }),
      AppColor.selectionBg,
    );
    expect(
      theme.menuButtonTheme.style!.backgroundColor!.resolve(<WidgetState>{
        WidgetState.hovered,
      }),
      AppColor.selectionHover,
    );
  });
}
