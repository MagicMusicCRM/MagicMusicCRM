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

/// Funding marker kept separate from the lesson's lifecycle color and icon.
class LessonSubscriptionBadge extends StatelessWidget {
  const LessonSubscriptionBadge({
    super.key,
    this.compact = false,
    this.iconOnly = false,
  });

  final bool compact;
  final bool iconOnly;

  static const tooltip = 'Покрыто абонементом';

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: iconOnly ? 2 : (compact ? 4 : 7),
          vertical: compact ? 1 : 2,
        ),
        decoration: BoxDecoration(
          color: AppColor.successSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColor.success.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.card_membership_outlined,
              color: AppColor.success,
              size: compact ? 10 : 12,
            ),
            if (!iconOnly) ...[
              SizedBox(width: compact ? 3 : 4),
              Text(
                compact ? 'Абон.' : 'Абонемент',
                style: const TextStyle(
                  color: AppColor.success,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
