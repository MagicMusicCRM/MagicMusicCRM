import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/messenger/inbox_logic.dart';

/// Segmented folder bar (Лиды / Ученики / Архив) for the staff chat list.
///
/// Each segment shows a gold unread badge when [unread][folder] > 0.
/// The currently [selected] segment is visually highlighted.
/// Tapping a segment calls [onSelected] with the corresponding [InboxFolder].
class InboxFolderBar extends StatelessWidget {
  final InboxFolder selected;
  final Map<InboxFolder, int> unread;
  final ValueChanged<InboxFolder> onSelected;

  const InboxFolderBar({
    super.key,
    required this.selected,
    required this.unread,
    required this.onSelected,
  });

  static const _labels = {
    InboxFolder.leads: 'Лиды',
    InboxFolder.students: 'Ученики',
    InboxFolder.archive: 'Архив',
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColor.input : const Color(0xFFE8E8EC);
    final selectedBg = AppColor.gold;
    final selectedFg = AppColor.onGold;
    final unselectedFg = AppColor.text2;

    return Container(
      height: 40,
      color: isDark ? AppColor.surface : const Color(0xFFF2F2F7),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 4),
      child: Row(
        children: InboxFolder.values.map((folder) {
          final isSelected = folder == selected;
          final count = unread[folder] ?? 0;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(folder),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isSelected ? selectedBg : bgColor,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _labels[folder]!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? selectedFg : unselectedFg,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          // Badge on selected tab: dark; badge on unselected: gold
                          color: isSelected
                              ? AppColor.onGold.withAlpha(40)
                              : AppColor.gold,
                          borderRadius:
                              BorderRadius.circular(AppRadius.icon),
                        ),
                        constraints: const BoxConstraints(minWidth: 22),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isSelected ? selectedFg : AppColor.onGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
