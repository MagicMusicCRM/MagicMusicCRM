import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// Pure UI helpers shared between [ClientCard] and the extracted sheet builders
/// (client_card_sheets.dart). None of these touch card state — they are plain
/// factories, so they live outside the State class and can be reused freely.

/// Outlined input decoration used across the card's text fields and dropdowns.
InputDecoration clientCardInputDecoration(
  ColorScheme cs, {
  String? label,
  String? hint,
  String? helperText,
  bool isDense = false,
  Widget? suffixIcon,
}) {
  final r = BorderRadius.circular(AppRadius.control);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helperText,
    isDense: isDense,
    suffixIcon: suffixIcon,
    enabledBorder: OutlineInputBorder(
      borderRadius: r,
      borderSide: BorderSide(color: cs.outlineVariant),
    ),
    border: OutlineInputBorder(
      borderRadius: r,
      borderSide: BorderSide(color: cs.outlineVariant),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: r,
      borderSide: const BorderSide(color: AppColor.gold, width: 2),
    ),
  );
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
