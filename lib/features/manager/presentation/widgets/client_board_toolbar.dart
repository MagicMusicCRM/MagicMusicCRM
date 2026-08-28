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
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final search = TextField(
                key: searchKey,
                controller: searchController,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppColor.bg,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
              );
              final filters = _ClientBoardFiltersButton(
                activeCount: activeFilterCount,
                onPressed: onFiltersPressed,
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: filters),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 320, child: search),
                  const SizedBox(width: 8),
                  filters,
                ],
              );
            },
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
      style: OutlinedButton.styleFrom(
        foregroundColor: hasActive ? AppColor.selectionText : AppColor.text,
        backgroundColor: hasActive ? AppColor.selectionBg : AppColor.bg,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: BorderSide(
          color: hasActive ? AppColor.selectionBorder : AppColor.borderStrong,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
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
