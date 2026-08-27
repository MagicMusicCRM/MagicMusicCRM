import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';

class ChatInfoTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  ChatInfoTabHeaderDelegate(this.tabBar);

  final Widget tabBar;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => tabBar;

  @override
  bool shouldRebuild(ChatInfoTabHeaderDelegate oldDelegate) => false;
}

class ChatInfoActionButton extends StatelessWidget {
  const ChatInfoActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isDark,
    this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? (isDark ? Colors.white : Colors.black);
    final labelColor =
        color ??
        (isDark
            ? TelegramColors.darkTextSecondary
            : TelegramColors.lightTextSecondary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isDark
                    ? TelegramColors.darkSurface
                    : TelegramColors.lightSurface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
          ],
        ),
      ),
    );
  }
}
