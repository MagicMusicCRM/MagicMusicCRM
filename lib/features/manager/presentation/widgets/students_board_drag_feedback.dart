import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

class StudentBoardDragFeedback extends StatelessWidget {
  const StudentBoardDragFeedback({
    super.key,
    required this.name,
    required this.phone,
  });

  final String name;
  final String phone;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: .03,
    child: Material(
      color: Colors.transparent,
      child: Builder(
        builder: (context) {
          final screenWidth = MediaQuery.sizeOf(context).width;
          final feedbackWidth = screenWidth < 360
              ? (screenWidth - 24).clamp(220.0, 300.0) - 24
              : 276.0;
          return Container(
            key: const ValueKey('student-card-drag-feedback'),
            width: feedbackWidth,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: AppTheme.primaryGold, width: 2),
              boxShadow: AppShadow.shLift,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.school_rounded,
                  size: 14,
                  color: AppTheme.primaryGold,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (phone.isNotEmpty)
                        Text(
                          phone,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.drag_indicator_rounded, size: 18),
              ],
            ),
          );
        },
      ),
    ),
  );
}
