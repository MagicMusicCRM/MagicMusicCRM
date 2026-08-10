import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';

class LessonStateBadge extends StatelessWidget {
  final LessonStateProjection projection;

  const LessonStateBadge({super.key, required this.projection});

  factory LessonStateBadge.fromMap(Map<String, dynamic> lesson, {Key? key}) =>
      LessonStateBadge(
        key: key,
        projection: LessonStateProjection.fromMap(lesson),
      );

  @override
  Widget build(BuildContext context) {
    final accent = projection.token.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: projection.token.soft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(projection.token.icon, color: accent, size: 11),
          const SizedBox(width: 4),
          Text(
            projection.label,
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class LessonTrialBadge extends StatelessWidget {
  final bool compact;

  const LessonTrialBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: AppColor.goldSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColor.goldLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            color: AppColor.gold,
            size: compact ? 9 : 11,
          ),
          SizedBox(width: compact ? 2 : 4),
          Text(
            compact ? 'Проб.' : 'Пробное',
            style: const TextStyle(
              color: AppColor.gold,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
