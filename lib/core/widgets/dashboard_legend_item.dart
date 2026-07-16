import 'package:flutter/material.dart';

/// Small colour-swatch + label legend row shared by the finance and management
/// dashboards. Previously duplicated as a private `_LegendItem` in each widget
/// (the architecture audit flagged the dashboards for copy-pasted chrome); this
/// is the single shared source.
class DashboardLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const DashboardLegendItem({
    super.key,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
