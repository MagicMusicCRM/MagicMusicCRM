import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/utils/status_color.dart';

void main() {
  group('statusColorFromValue', () {
    test('maps semantic tokens without throwing (regression: FFinfo crash)', () {
      // Previously `int.parse("FF$token", radix:16)` threw FormatException.
      expect(statusColorFromValue('info'), const Color(0xFF3B82F6));
      expect(statusColorFromValue('danger'), AppTheme.danger);
      expect(statusColorFromValue('success'), AppTheme.success);
      expect(statusColorFromValue('warning'), AppTheme.warning);
      expect(statusColorFromValue('primaryPurple'), AppTheme.primaryGold);
    });

    test('parses hex with and without # / alpha', () {
      expect(statusColorFromValue('8B5CF6'), const Color(0xFF8B5CF6));
      expect(statusColorFromValue('#8B5CF6'), const Color(0xFF8B5CF6));
      expect(statusColorFromValue('FF8B5CF6'), const Color(0xFF8B5CF6));
    });

    test('falls back for null / empty / garbage instead of throwing', () {
      expect(statusColorFromValue(null), AppTheme.primaryGold);
      expect(statusColorFromValue(''), AppTheme.primaryGold);
      expect(statusColorFromValue('not-a-color'), AppTheme.primaryGold);
      expect(
        statusColorFromValue('zzz', fallback: AppTheme.success),
        AppTheme.success,
      );
    });
  });
}
