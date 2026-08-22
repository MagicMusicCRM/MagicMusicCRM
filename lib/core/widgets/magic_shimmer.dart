import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// Token-driven skeleton primitives matching the v7 prototype `.skel`
/// (base `#1d1d21` + a `rgba(255,255,255,.06)` sweep over `1.15s`).
///
/// Additive P0 component — not mounted anywhere yet. Reskin phases replace the
/// ad-hoc skeletons in `core/widgets/skeletons.dart` with these as screens are
/// migrated. Reduced-motion: the sweep stops when the platform disables
/// animations, leaving a static base box (mirrors `.skel::after{animation:none}`).
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = AppRadius.sm,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.shimmer,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Run the sweep only when animations are enabled, and react to the user
    // toggling reduced-motion at runtime (mirrors `.skel::after{animation:none}`).
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final base = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: const ColoredBox(color: AppColor.skeletonBase),
      ),
    );
    if (reduceMotion) return base;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColor.skeletonBase),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: const [
                        Color(0x00FFFFFF),
                        AppColor.skeletonHighlight,
                        Color(0x00FFFFFF),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                      transform: _SweepTransform(_controller.value * 2 - 1),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A skeleton text line (`.skel-line{height:11px;border-radius:6px}`).
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.width, this.height = 11});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(width: width, height: height, radius: AppRadius.sm);
  }
}

/// Translates a gradient horizontally by [t] (fraction of the bounds width,
/// `-1`..`1`) so the highlight sweeps left→right.
class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.t);

  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * t, 0, 0);
  }
}
