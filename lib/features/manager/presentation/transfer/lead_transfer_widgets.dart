import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'lead_transfer_controller.dart';

/// A self-registering drop target for the transfer flow.
///
/// On mount it registers a [GlobalKey] (attached to the rendered child) with the
/// [controller] so the single dragging [Draggable] can hit-test it via global
/// pointer positions. The [builder] is rebuilt with the live `hovering` /
/// `progress` state so the zone can show its dashed outline + fill.
class TransferDropZone extends StatefulWidget {
  final String zoneId;
  final TransferZoneKind kind;
  final String? value;
  final String? label;
  final LeadTransferController controller;
  final Widget Function(BuildContext context, bool hovering, double progress)
      builder;

  const TransferDropZone({
    super.key,
    required this.zoneId,
    required this.kind,
    required this.controller,
    required this.builder,
    this.value,
    this.label,
  });

  @override
  State<TransferDropZone> createState() => _TransferDropZoneState();
}

class _TransferDropZoneState extends State<TransferDropZone> {
  final GlobalKey _zoneKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.controller.registerZone(
      widget.zoneId,
      _zoneKey,
      widget.kind,
      value: widget.value,
      label: widget.label,
    );
  }

  @override
  void didUpdateWidget(TransferDropZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoneId != widget.zoneId) {
      oldWidget.controller.unregisterZone(oldWidget.zoneId);
    }
    widget.controller.registerZone(
      widget.zoneId,
      _zoneKey,
      widget.kind,
      value: widget.value,
      label: widget.label,
    );
  }

  @override
  void dispose() {
    widget.controller.unregisterZone(widget.zoneId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final bool hovering;
        if (widget.kind == TransferZoneKind.column) {
          hovering = c.hoverColumnStatus != null &&
              c.hoverColumnStatus == widget.value;
        } else {
          hovering = c.confirmingZoneId == widget.zoneId;
        }
        return ValueListenableBuilder<double>(
          valueListenable: c.progress,
          builder: (context, progressValue, _) {
            final progress = hovering &&
                    widget.kind != TransferZoneKind.column &&
                    c.confirmingZoneId == widget.zoneId
                ? progressValue
                : 0.0;
            return KeyedSubtree(
              key: _zoneKey,
              child: widget.builder(context, hovering, progress),
            );
          },
        );
      },
    );
  }
}

/// A thin determinate progress bar used in the expanded «Ученики» field and the
/// branch chips during the confirmation hold. Uses transfer-cyan per the
/// palette (`cyan = conversion/transfer`).
class TransferProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color color;

  const TransferProgressBar({
    super.key,
    required this.value,
    this.height = 4,
    this.color = AppColor.transferCyan,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(color: color.withValues(alpha: 0.18)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded-rectangle dashed border, used to mark active drop zones (the
/// «Ученики» field, the target student column).
class DashedRoundedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  const DashedRoundedBorder({
    super.key,
    required this.child,
    required this.color,
    this.radius = AppRadius.card,
    this.strokeWidth = 1.6,
    this.dash = 6,
    this.gap = 4,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRectPainter(
        color: color,
        radius: radius,
        strokeWidth: strokeWidth,
        dash: dash,
        gap: gap,
      ),
      child: child,
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  _DashedRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dash,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect.deflate(strokeWidth / 2));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.dash != dash ||
      old.gap != gap;
}

/// The lifted card that follows the pointer for the whole flow (the [Draggable]
/// `feedback`). It listens to the [controller] so its footer label/percent track
/// the live phase (over «Ученики», over a branch, over a column …).
class TransferGhostCard extends StatelessWidget {
  final LeadTransferController controller;
  final Map<String, dynamic> lead;
  final double width;

  const TransferGhostCard({
    super.key,
    required this.controller,
    required this.lead,
    this.width = 276,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = lead['name']?.toString() ?? '';
    final lastName = lead['last_name']?.toString() ?? '';
    final name = '$firstName $lastName'.trim();
    final displayName = name.isEmpty ? 'Без имени' : name;
    final phone = lead['phone']?.toString() ?? '';
    final custom = lead['custom_data'];
    final discipline =
        custom is Map ? (custom['discipline']?.toString() ?? '') : '';
    final trials = lead['trial_lessons_count'];
    final hasTrial =
        (trials is num ? trials.toInt() : int.tryParse('$trials') ?? 0) > 0;

    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return ValueListenableBuilder<double>(
            valueListenable: controller.progress,
            builder: (context, progress, _) {
              final (footerLeft, footerRight) = _footer(progress);
              return Transform.rotate(
                angle: 0.02,
                child: Container(
                  width: width,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColor.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColor.actionBlue, width: 1.6),
                    boxShadow: AppShadow.shLift,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColor.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.drag_indicator_rounded,
                            size: 18,
                            color: AppColor.text2,
                          ),
                        ],
                      ),
                      if (phone.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            phone,
                            style: const TextStyle(
                              color: AppColor.text2,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (discipline.isNotEmpty || hasTrial)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (discipline.isNotEmpty)
                                _GhostTag(
                                  text: discipline,
                                  color: AppColor.gold,
                                ),
                              if (hasTrial)
                                _GhostTag(
                                  text: 'Пробный',
                                  color: AppColor.transferCyan,
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              footerLeft,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColor.text2,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          if (footerRight.isNotEmpty)
                            Text(
                              footerRight,
                              style: const TextStyle(
                                color: AppColor.transferCyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  (String, String) _footer(double progress) {
    final pct = '${(progress * 100).round()}%';
    if (controller.phase == LeadTransferPhase.onLeads) {
      if (controller.confirmingZoneId != null) return ('над «Ученики»', pct);
      return ('в руках', '');
    }
    // students phase
    if (controller.hoverColumnStatus != null) {
      return ('над колонкой', '');
    }
    if (controller.confirmingZoneId != null) {
      return ('филиал', pct);
    }
    return ('вкладка Ученики', '');
  }
}

class _GhostTag extends StatelessWidget {
  final String text;
  final Color color;

  const _GhostTag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
