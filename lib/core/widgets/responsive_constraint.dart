import 'package:flutter/material.dart';

/// A widget that constrains its child's width to 450px on desktop/large screens,
/// and centers it. On mobile, it fills the width.
class ResponsiveConstraint extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final Color? backgroundColor;

  const ResponsiveConstraint({
    super.key,
    required this.child,
    this.maxWidth = 450.0,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
