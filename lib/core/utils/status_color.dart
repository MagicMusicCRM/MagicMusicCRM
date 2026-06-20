import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

/// Blue used for the semantic `info` token (no dedicated AppTheme token).
const Color _infoBlue = Color(0xFF3B82F6);

/// Resolves a lead/status color coming from the backend, which may be EITHER a
/// hex string (`"8B5CF6"`, `"#8B5CF6"`, `"FF8B5CF6"`) OR a semantic token
/// (`"danger"`, `"success"`, `"warning"`, `"primaryPurple"`, `"info"` — emitted
/// by the HolliHop import's `colorForStatus`). Never throws: an unparseable
/// value falls back instead of crashing the widget (was `int.parse` →
/// `FormatException: Invalid radix-16` on tokens like `info`).
Color statusColorFromValue(
  Object? value, {
  Color fallback = AppTheme.primaryGold,
}) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return fallback;
  switch (raw.toLowerCase()) {
    case 'danger':
    case 'error':
    case 'red':
      return AppTheme.danger;
    case 'success':
    case 'green':
      return AppTheme.success;
    case 'warning':
    case 'amber':
    case 'orange':
      return AppTheme.warning;
    case 'primarypurple':
    case 'primary':
    case 'purple':
    case 'gold':
      return AppTheme.primaryGold;
    case 'info':
    case 'blue':
      return _infoBlue;
  }
  // Hex path: accept #RRGGBB / RRGGBB / AARRGGBB.
  var hex = raw.replaceAll('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? fallback : Color(parsed);
}
