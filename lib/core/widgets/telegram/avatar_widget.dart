import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';

/// Telegram-style circular avatar with gradient background and initials fallback.
class TelegramAvatar extends StatelessWidget {
  final String? name;
  final String? avatarUrl;
  final String? uniqueId;
  final double radius;
  final IconData? icon;

  const TelegramAvatar({
    super.key,
    this.name,
    this.avatarUrl,
    this.uniqueId,
    this.radius = 24,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(avatarUrl!),
      );
    }

    final id = uniqueId ?? name ?? 'default';
    final gradientColors = TelegramColors.avatarGradientFor(id);
    final initials = name != null ? TelegramColors.initialsFrom(name!) : '?';

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ),
      ),
      child: Center(
        child: icon != null
            ? Icon(icon, color: Colors.white, size: radius * 0.9)
            : Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: radius * 0.7,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
