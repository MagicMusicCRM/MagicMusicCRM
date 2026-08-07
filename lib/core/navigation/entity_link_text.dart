import 'package:flutter/material.dart';

/// Visual contract for internal related records: the entity label is the link.
class EntityLinkText extends StatelessWidget {
  const EntityLinkText({
    super.key,
    required this.text,
    required this.onPressed,
    this.style,
    this.maxLines,
  });

  final String text;
  final VoidCallback onPressed;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium;
    return Semantics(
      link: true,
      button: true,
      label: text,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(vertical: 2),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.centerLeft,
        ),
        child: Text(
          text,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: base?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
