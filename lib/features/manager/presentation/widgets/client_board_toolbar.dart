import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

class ClientBoardToolbar extends StatelessWidget {
  const ClientBoardToolbar({
    required this.title,
    required this.searchKey,
    required this.searchController,
    required this.searchHint,
    required this.activeFilterCount,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.onFiltersPressed,
    this.inlineFilters,
    this.searching = false,
    super.key,
  });

  final String title;
  final Key searchKey;
  final TextEditingController searchController;
  final String searchHint;
  final int activeFilterCount;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onClearSearch;
  final VoidCallback onFiltersPressed;
  final Widget? inlineFilters;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(
                  width: 240,
                  child: TextField(
                    key: searchKey,
                    controller: searchController,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      hintText: searchHint,
                      suffixIcon: searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Очистить поиск',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: onClearSearch,
                            ),
                    ),
                    onChanged: onSearchChanged,
                    onSubmitted: onSearchSubmitted,
                  ),
                ),
                const SizedBox(width: 8),
                _ClientBoardFiltersButton(
                  activeCount: activeFilterCount,
                  onPressed: onFiltersPressed,
                ),
              ],
            ),
          ),
          ?inlineFilters,
          if (searching)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Text(
                    'идёт поиск…',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ClientBoardFiltersButton extends StatelessWidget {
  const _ClientBoardFiltersButton({
    required this.activeCount,
    required this.onPressed,
  });

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final hasActive = activeCount > 0;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: hasActive
          ? OutlinedButton.styleFrom(
              foregroundColor: AppColor.gold,
              side: const BorderSide(color: AppColor.goldLine),
            )
          : null,
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Фильтры'),
          if (hasActive) ...[
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppColor.gold,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '$activeCount',
                style: const TextStyle(
                  color: AppColor.onGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
