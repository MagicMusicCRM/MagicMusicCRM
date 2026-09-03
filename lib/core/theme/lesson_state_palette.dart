import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// Closed visual vocabulary for operational lesson surfaces.
///
/// Trial and subscription coverage use separate badges. Lesson backgrounds
/// always express lifecycle, including when a subscription reserves the lesson.
enum LessonStateToken { booked, completed, conflict }

class LessonStateProjection {
  final LessonStateToken token;
  final String state;
  final String label;

  const LessonStateProjection({
    required this.token,
    required this.state,
    required this.label,
  });

  factory LessonStateProjection.fromMap(
    Map<String, dynamic> lesson, {
    bool? hasConflict,
  }) {
    return lessonStateProjection(
      lifecycleState:
          lesson['lifecycle_state']?.toString() ??
          lesson['lifecycleState']?.toString(),
      rawStatus: lesson['status']?.toString(),
      hasConflict: hasConflict ?? _mapHasConflicts(lesson),
    );
  }
}

LessonStateProjection lessonStateProjection({
  String? lifecycleState,
  String? rawStatus,
  bool hasConflict = false,
}) {
  final state = _normalizeState(lifecycleState, rawStatus);
  final token =
      hasConflict ||
          state == 'settlement_pending' ||
          state == 'cancelled' ||
          state == 'rescheduled'
      ? LessonStateToken.conflict
      : state == 'successfully_completed'
      ? LessonStateToken.completed
      : LessonStateToken.booked;
  return LessonStateProjection(token: token, state: state, label: token.label);
}

bool _mapHasConflicts(Map<String, dynamic> lesson) {
  final raw = lesson['conflict_types'] ?? lesson['conflictTypes'];
  return switch (raw) {
    final Iterable<dynamic> values => values.isNotEmpty,
    final String value => value.trim().isNotEmpty,
    _ => false,
  };
}

/// Coverage comes from an actual reservation, never an intended funding choice.
bool lessonHasSubscriptionCoverage(Map<String, dynamic> lesson) {
  if ((lesson['reservation_state'] ?? lesson['reservationState']) ==
      'reserved') {
    return true;
  }
  final markers = lesson['settlement_markers'] ?? lesson['settlementMarkers'];
  return markers is Iterable &&
      markers.whereType<Map>().any(
        (marker) => marker['key'] == 'subscription_reserved',
      );
}

String _normalizeState(String? lifecycleState, String? rawStatus) {
  final state = lifecycleState?.trim();
  if (state != null && state.isNotEmpty) return state;
  return switch (rawStatus?.trim()) {
    'settlement_pending' => 'settlement_pending',
    'completed' => 'successfully_completed',
    'rescheduled' => 'rescheduled',
    'cancelled' => 'cancelled',
    _ => 'scheduled',
  };
}

extension LessonStateTokenColors on LessonStateToken {
  Color get accent => switch (this) {
    LessonStateToken.booked => AppColor.actionBlue,
    LessonStateToken.completed => AppColor.success,
    LessonStateToken.conflict => AppColor.danger,
  };

  Color get soft => switch (this) {
    LessonStateToken.booked => AppColor.actionBlue.withValues(alpha: 0.12),
    LessonStateToken.completed => AppColor.success.withValues(alpha: 0.12),
    LessonStateToken.conflict => AppColor.dangerSoft,
  };

  String get label => switch (this) {
    LessonStateToken.booked => 'Забронировано',
    LessonStateToken.completed => 'Завершено',
    LessonStateToken.conflict => 'Конфликт',
  };

  IconData get icon => switch (this) {
    LessonStateToken.booked => Icons.event_available_outlined,
    LessonStateToken.completed => Icons.check_circle_outline_rounded,
    LessonStateToken.conflict => Icons.warning_amber_rounded,
  };
}

/// Shared non-semantic color preview for configurable lesson decisions.
Color lessonDecisionColorToken(String? token) => switch (token) {
  'success' => AppColor.success,
  'warning' => AppColor.warning,
  'info' || 'blue' || 'cyan' => AppColor.actionBlue,
  'violet' => const Color(0xFF7C5CBF),
  _ => AppColor.text2,
};
