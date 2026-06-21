import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// One row in a [showMagicMenu] pop-menu (`.pm-item`).
class MagicMenuItem<T> {
  const MagicMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.danger = false,
    this.dividerAfter = false,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Destructive styling (`.pm-item.danger` — red label/icon).
  final bool danger;

  /// Renders a `.pm-sep` divider below this item.
  final bool dividerAfter;
}

/// Opens a v7-styled pop-menu (`.popmenu`) anchored at [globalPosition]
/// (typically `details.globalPosition` from a tap or long-press) and resolves
/// to the chosen item's value, or `null` if dismissed.
///
/// Canonical replacement for ad-hoc `showMenu`/`PopupMenuButton` call sites;
/// additive in P0.
Future<T?> showMagicMenu<T>(
  BuildContext context, {
  required Offset globalPosition,
  required List<MagicMenuItem<T>> items,
}) {
  final overlay =
      Overlay.of(context, rootOverlay: true).context.findRenderObject()
          as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(globalPosition, globalPosition),
    Offset.zero & overlay.size,
  );

  final entries = <PopupMenuEntry<T>>[];
  for (final item in items) {
    entries.add(_MagicMenuRow<T>(item: item));
    if (item.dividerAfter) {
      entries.add(const PopupMenuDivider(height: 11));
    }
  }

  return showMenu<T>(
    context: context,
    position: position,
    color: AppColor.overlay,
    elevation: 0,
    constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.overlay),
      side: const BorderSide(color: AppColor.divider),
    ),
    items: entries,
  );
}

class _MagicMenuRow<T> extends PopupMenuEntry<T> {
  const _MagicMenuRow({required this.item});

  final MagicMenuItem<T> item;

  @override
  double get height => 40;

  @override
  bool represents(T? value) => value == item.value;

  @override
  State<_MagicMenuRow<T>> createState() => _MagicMenuRowState<T>();
}

class _MagicMenuRowState<T> extends State<_MagicMenuRow<T>> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final color = item.danger ? AppColor.menuDanger : AppColor.menuItemText;
    final iconColor = item.danger ? AppColor.menuDanger : AppColor.text2;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      hoverColor: item.danger ? AppColor.dangerSoft : AppColor.menuItemHover,
      onTap: () => Navigator.of(context).pop<T>(item.value),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, size: 17, color: iconColor),
              const SizedBox(width: 11),
            ],
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
