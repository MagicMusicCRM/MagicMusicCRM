import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';

/// Telegram-style circular avatar with gradient background and initials fallback.
class TelegramAvatar extends ConsumerStatefulWidget {
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
  ConsumerState<TelegramAvatar> createState() => _TelegramAvatarState();
}

class _TelegramAvatarState extends ConsumerState<TelegramAvatar> {
  String? _resolvedAvatarUrl;
  String? _sourceAvatarUrl;

  @override
  void initState() {
    super.initState();
    _resolveAvatarUrl();
  }

  @override
  void didUpdateWidget(covariant TelegramAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) {
      _resolveAvatarUrl();
    }
  }

  Future<void> _resolveAvatarUrl() async {
    final sourceUrl = widget.avatarUrl;
    _sourceAvatarUrl = sourceUrl;
    if (sourceUrl == null || sourceUrl.isEmpty) {
      setState(() => _resolvedAvatarUrl = null);
      return;
    }

    try {
      final resolved = await ref
          .read(chatAttachmentServiceProvider)
          .resolveUrl(sourceUrl);
      if (!mounted || sourceUrl != _sourceAvatarUrl) return;
      setState(() => _resolvedAvatarUrl = resolved);
    } catch (error) {
      debugPrint('Avatar URL resolve error: $error');
      if (mounted && sourceUrl == _sourceAvatarUrl) {
        setState(() => _resolvedAvatarUrl = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = _resolvedAvatarUrl != null && _resolvedAvatarUrl!.isNotEmpty;
    final id = widget.uniqueId ?? widget.name ?? 'default';
    final gradientColors = TelegramColors.avatarGradientFor(id);
    final initials = widget.name != null
        ? TelegramColors.initialsFrom(widget.name!)
        : '?';

    Widget child;
    if (hasUrl) {
      final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
      final cacheSize = (widget.radius * 2 * devicePixelRatio).round();
      child = Image.network(
        _resolvedAvatarUrl!,
        fit: BoxFit.cover,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        errorBuilder: (context, error, stackTrace) =>
            _buildInitials(gradientColors, initials),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildInitials(gradientColors, initials);
        },
      );
    } else {
      child = _buildInitials(gradientColors, initials);
    }

    return Container(
      width: widget.radius * 2,
      height: widget.radius * 2,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildInitials(List<Color> gradientColors, String initials) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ),
      ),
      child: Center(
        child: widget.icon != null
            ? Icon(widget.icon, color: Colors.white, size: widget.radius * 0.9)
            : Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.radius * 0.7,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
