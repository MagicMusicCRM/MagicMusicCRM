import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// Pure UI helpers shared between [ClientCard] and the extracted sheet builders
/// (client_card_sheets.dart). None of these touch card state — they are plain
/// factories, so they live outside the State class and can be reused freely.

InputDecorationTheme _clientCardInputTheme() {
  final radius = BorderRadius.circular(AppRadius.control);
  final enabledBorder = OutlineInputBorder(
    borderRadius: radius,
    borderSide: const BorderSide(color: AppColor.borderSoft),
  );
  return InputDecorationTheme(
    filled: true,
    fillColor: AppColor.surface,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    labelStyle: const TextStyle(
      color: AppColor.text2,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    ),
    floatingLabelStyle: const TextStyle(
      color: AppColor.selectionText,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
    hintStyle: const TextStyle(color: AppColor.text3),
    helperStyle: const TextStyle(color: AppColor.text2, fontSize: 12),
    prefixIconColor: AppColor.text2,
    suffixIconColor: AppColor.text2,
    border: enabledBorder,
    enabledBorder: enabledBorder,
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColor.brandSolid, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColor.danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColor.danger, width: 1.5),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColor.divider),
    ),
  );
}

/// A scoped, presentation-only theme for the editable client canvas.
///
/// It keeps native Flutter controls and their overlay menus on the same
/// semantic surface without changing any picker behaviour or app-wide theme.
ThemeData clientCardControlTheme(ThemeData base) {
  final inputTheme = _clientCardInputTheme();
  final menuButtonStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.fromHeight(46)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    ),
    foregroundColor: const WidgetStatePropertyAll(AppColor.text),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused) ||
          states.contains(WidgetState.selected)) {
        return AppColor.selectionBg;
      }
      if (states.contains(WidgetState.hovered)) {
        return AppColor.selectionHover;
      }
      return AppColor.overlay;
    }),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
    ),
  );
  return base.copyWith(
    inputDecorationTheme: inputTheme,
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: const TextStyle(color: AppColor.text, fontSize: 15),
      inputDecorationTheme: inputTheme,
      disabledColor: AppColor.disabledText,
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColor.overlay),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(AppSpace.xs)),
        side: const WidgetStatePropertyAll(
          BorderSide(color: AppColor.borderSoft),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.overlay),
          ),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(style: menuButtonStyle),
  );
}

/// Outlined input decoration used across the card's text fields and dropdowns.
InputDecoration clientCardInputDecoration(
  ColorScheme cs, {
  String? label,
  String? hint,
  String? helperText,
  String? errorText,
  bool isDense = false,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helperText,
    errorText: errorText,
    isDense: isDense,
    suffixIcon: suffixIcon,
  ).applyDefaults(_clientCardInputTheme());
}

/// Primary gold action button used in sheet action rows.
Widget clientCardGoldButton(String label, VoidCallback? onPressed) {
  return FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: AppColor.gold,
      foregroundColor: AppColor.onGold,
      disabledBackgroundColor: AppColor.goldSoft,
      disabledForegroundColor: AppColor.text2,
      elevation: 0,
      shadowColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    child: Text(label),
  );
}

/// Secondary ghost/outlined action button used in sheet action rows.
Widget clientCardGhostButton(String label, VoidCallback? onPressed) {
  return OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColor.text,
      side: const BorderSide(color: AppColor.divider),
      padding: const EdgeInsets.symmetric(vertical: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    child: Text(label),
  );
}
