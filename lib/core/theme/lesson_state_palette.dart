import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// Closed visual vocabulary for every Lesson surface.
enum LessonStateToken { neutral, success, rescheduled }

class LessonStateProjection {
  final LessonStateToken token;
  final String state;
  final String label;
  final String? reservationState;

  const LessonStateProjection({
    required this.token,
    required this.state,
    required this.label,
    this.reservationState,
  });

  factory LessonStateProjection.fromMap(Map<String, dynamic> lesson) {
    return lessonStateProjection(
      lifecycleState:
          lesson['lifecycle_state']?.toString() ??
          lesson['lifecycleState']?.toString(),
      legacyStatus: lesson['status']?.toString(),
      reservationState:
          lesson['reservation_state']?.toString() ??
          lesson['reservationState']?.toString(),
    );
  }
}

LessonStateProjection lessonStateProjection({
  String? lifecycleState,
  String? legacyStatus,
  String? reservationState,
}) {
  final state = _normalizeState(lifecycleState, legacyStatus);
  final covered = reservationState == 'reserved';
  final token = state == 'rescheduled'
      ? LessonStateToken.rescheduled
      : state == 'successfully_completed' || covered
      ? LessonStateToken.success
      : LessonStateToken.neutral;
  final label = switch (state) {
    'successfully_completed' => 'Завершено',
    'rescheduled' => 'Перенесено',
    'cancelled' => 'Отменено',
    _ when covered => 'Забронировано',
    _ => 'Запланировано',
  };
  return LessonStateProjection(
    token: token,
    state: state,
    label: label,
    reservationState: reservationState,
  );
}

String _normalizeState(String? lifecycleState, String? legacyStatus) {
  final state = lifecycleState?.trim();
  if (state != null && state.isNotEmpty) return state;
  return switch (legacyStatus?.trim()) {
    'completed' => 'successfully_completed',
    'rescheduled' => 'rescheduled',
    'cancelled' => 'cancelled',
    _ => 'scheduled',
  };
}

extension LessonStateTokenColors on LessonStateToken {
  Color get accent => switch (this) {
    LessonStateToken.neutral => AppColor.text2,
    LessonStateToken.success => AppColor.success,
    LessonStateToken.rescheduled => AppColor.danger,
  };

  Color get soft => switch (this) {
    LessonStateToken.neutral => AppColor.divider.withValues(alpha: 0.48),
    LessonStateToken.success => AppColor.success.withValues(alpha: 0.12),
    LessonStateToken.rescheduled => AppColor.dangerSoft,
  };
}
