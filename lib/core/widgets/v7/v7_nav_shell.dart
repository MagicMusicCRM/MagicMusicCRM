import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../../theme/telegram_colors.dart';
import 'magic_menu.dart';

/// One destination in a [V7NavShell].
class V7NavDestination {
  const V7NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Optional gold count pill (v7 `.rb` / `.tb-badge`); hidden when `<= 0`.
  final int badgeCount;
}

/// v7 navigation shell — a desktop left rail (`.rail`, 76px) or a phone bottom
/// bar (`.tabbar`, 62px). On phone, a role with more than five destinations
/// shows four primary tabs plus an «Ещё» overflow (a [showMagicMenu] pop-menu),
/// mirroring the prototype `tabbar()` logic exactly (4 primary + «Ещё» when
/// `items.length > 5`).
///
/// Presentational only: [selectedIndex] / [onSelected] index into
/// [destinations]; RBAC (which destinations a role sees) is decided by the
/// caller. Theme-adaptive so light mode keeps working.
class V7NavShell extends StatelessWidget {
  const V7NavShell({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.isDesktop,
  });

  final List<V7NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return isDesktop ? _buildRail(context) : _buildBar(context);
  }

  // ── Desktop rail ───────────────────────────────────────────────────────────
  Widget _buildRail(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColor.sidebar : TelegramColors.lightSidebar;
    final divider = isDark ? AppColor.divider : TelegramColors.lightDivider;

    return Container(
      width: 76,
      decoration: BoxDecoration(
        color: bg,
        border: Border(right: BorderSide(color: divider)),
      ),
      child: SafeArea(
        right: false,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 0),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                children: [
                  _brand(),
                  const SizedBox(height: 8),
                  for (var i = 0; i < destinations.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _RailItem(
                      destination: destinations[i],
                      selected: i == selectedIndex,
                      isDark: isDark,
                      onTap: () => onSelected(i),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2418), Color(0xFF1D1A12)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.icon),
        border: Border.all(color: AppColor.goldLine),
      ),
      child: const Icon(Icons.music_note_rounded, size: 20, color: AppColor.gold),
    );
  }

  // ── Phone bottom bar ─────────────────────────────────────────────────────────
  Widget _buildBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColor.sidebar : TelegramColors.lightSidebar;
    final divider = isDark ? AppColor.divider : TelegramColors.lightDivider;

    // v7 tabbar(): >5 destinations → 4 primary + «Ещё»; otherwise show all.
    final hasOverflow = destinations.length > 5;
    final primaryCount = hasOverflow ? 4 : destinations.length;
    final overflowActive =
        hasOverflow && selectedIndex >= primaryCount;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < primaryCount; i++)
                Expanded(
                  child: _BarTab(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    isDark: isDark,
                    onTap: () => onSelected(i),
                  ),
                ),
              if (hasOverflow)
                Expanded(
                  // Own Builder so the overflow menu anchors to the «Ещё» tab's
                  // render box, not the full-width bar.
                  child: Builder(
                    builder: (tabContext) => _BarTab(
                      destination: const V7NavDestination(
                        icon: Icons.more_horiz_rounded,
                        selectedIcon: Icons.more_horiz_rounded,
                        label: 'Ещё',
                      ),
                      selected: overflowActive,
                      isDark: isDark,
                      onTap: () => _openMore(tabContext, primaryCount),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMore(BuildContext context, int primaryCount) async {
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box != null
        ? box.localToGlobal(Offset(box.size.width / 2, 0))
        : Offset.zero;
    final picked = await showMagicMenu<int>(
      context,
      globalPosition: anchor,
      items: [
        for (var i = primaryCount; i < destinations.length; i++)
          MagicMenuItem<int>(
            value: i,
            label: destinations[i].label,
            icon: destinations[i].icon,
          ),
      ],
    );
    if (picked != null) onSelected(picked);
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final V7NavDestination destination;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final idle = isDark ? AppColor.text2 : TelegramColors.lightTextSecondary;
    final fg = selected ? AppColor.gold : idle;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          width: 68,
          height: 54,
          decoration: BoxDecoration(
            color: selected ? AppColor.goldSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _IconWithBadge(
                icon: selected ? destination.selectedIcon : destination.icon,
                color: fg,
                size: 21,
                badgeCount: destination.badgeCount,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  destination.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  // Clamp scaling so big system fonts don't blow up the tiny
                  // 9.5px label out of the fixed-height rail item.
                  textScaler: MediaQuery.textScalerOf(context)
                      .clamp(maxScaleFactor: 1.2),
                  style: TextStyle(
                    color: selected
                        ? (isDark
                            ? AppColor.text
                            : TelegramColors.lightTextPrimary)
                        : idle,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarTab extends StatelessWidget {
  const _BarTab({
    required this.destination,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final V7NavDestination destination;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final idle = isDark ? AppColor.text2 : TelegramColors.lightTextSecondary;
    final fg = selected ? AppColor.gold : idle;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _IconWithBadge(
              icon: selected ? destination.selectedIcon : destination.icon,
              color: fg,
              size: 23,
              badgeCount: destination.badgeCount,
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                destination.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                // Clamp scaling so big system fonts don't overflow the fixed
                // 62px bottom-bar height.
                textScaler:
                    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
                style: TextStyle(
                  color: fg,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconWithBadge extends StatelessWidget {
  const _IconWithBadge({
    required this.icon,
    required this.color,
    required this.size,
    required this.badgeCount,
  });

  final IconData icon;
  final Color color;
  final double size;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: size, color: color);
    if (badgeCount <= 0) return iconWidget;

    return Badge(
      label: Text('$badgeCount'),
      backgroundColor: AppColor.gold,
      textColor: AppColor.onGold,
      child: iconWidget,
    );
  }
}
