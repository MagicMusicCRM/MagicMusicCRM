import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// Keeps long values readable in both dialog forms and narrow phone sheets.
class ResponsiveDetailRow extends StatelessWidget {
  const ResponsiveDetailRow({
    required this.label,
    required this.value,
    this.valueWidget,
    super.key,
  });

  final String label;
  final String value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelWidget = Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final displayedValue =
        valueWidget ??
        Text(
          value,
          textAlign: TextAlign.start,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 520 * textScale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [labelWidget, const SizedBox(height: 4), displayedValue],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: constraints.maxWidth * 0.36, child: labelWidget),
            const SizedBox(width: AppSpace.md),
            Expanded(child: displayedValue),
          ],
        );
      },
    );
  }
}
