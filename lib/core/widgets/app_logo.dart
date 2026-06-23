import 'package:flutter/material.dart';

/// The real Magic Music school logo (assets/icon.png).
///
/// Use this everywhere a brand mark is needed instead of the placeholder
/// `Icons.music_note_rounded`. The image already contains the «Magic Music»
/// wordmark, so screens that show it don't need a separate text wordmark.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
