import 'dart:async';

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/v7/adaptive_surface.dart';

class SearchableSelectItem {
  final String id;
  final String label;
  final String? subtitle;
  final String? avatarUrl;
  final Map<String, dynamic>? data;

  SearchableSelectItem({
    required this.id,
    required this.label,
    this.subtitle,
    this.avatarUrl,
    this.data,
  });
}

class SearchableSelect extends StatefulWidget {
  final String title;
  final String hintText;
  final List<SearchableSelectItem> items;
  final String? selectedId;
  final Function(SearchableSelectItem?) onSelected;
  final bool isNullable;
  final bool embedded;

  /// Optional SERVER-side search. When set, keystrokes are debounced (350 ms)
  /// and this callback replaces the local filter, so the picker can find
  /// records beyond the pre-loaded page ([items] then only seeds the initial
  /// list). Without it the sheet filters [items] client-side as before.
  final Future<List<SearchableSelectItem>> Function(String query)? onSearch;

  const SearchableSelect({
    super.key,
    required this.title,
    required this.hintText,
    required this.items,
    required this.onSelected,
    this.selectedId,
    this.isNullable = true,
    this.onSearch,
    this.embedded = false,
  });

  @override
  State<SearchableSelect> createState() => _SearchableSelectState();

  static void show({
    required BuildContext context,
    required String title,
    required String hintText,
    required List<SearchableSelectItem> items,
    required Function(SearchableSelectItem?) onSelected,
    String? selectedId,
    bool isNullable = true,
    Future<List<SearchableSelectItem>> Function(String query)? onSearch,
  }) {
    unawaited(
      showMagicAdaptiveSurface<void>(
        context,
        kind: AppSurfaceKind.selection,
        title: title,
        icon: Icons.search_rounded,
        builder: (context) => SearchableSelect(
          title: title,
          hintText: hintText,
          items: items,
          onSelected: onSelected,
          selectedId: selectedId,
          isNullable: isNullable,
          onSearch: onSearch,
          embedded: true,
        ),
      ),
    );
  }
}

class _SearchableSelectState extends State<SearchableSelect> {
  final TextEditingController _searchController = TextEditingController();
  List<SearchableSelectItem> _filteredItems = [];

  /// How many matches a search shows. Requirement: the five best, not a wall
  /// of results to scroll through.
  static const _maxResults = 5;

  Timer? _searchDebounce;
  bool _searching = false;
  // Latest-wins guard: a slow response for an old query must not overwrite
  // the results of the query typed after it.
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Score a match: lower is better. A plain `contains` filter puts «Петров
  /// Иван» and «Иванов Пётр» in whatever order the list happened to be in, so
  /// the five shown for "иван" were not the five best.
  static int _matchScore(SearchableSelectItem item, String query) {
    final label = item.label.toLowerCase();
    if (label == query) return 0;
    if (label.startsWith(query)) return 1;
    // A hit at a word boundary («Иван» in «Петров Иван») beats one buried
    // mid-word («иван» in «Селиванов»).
    if (label.contains(' $query')) return 2;
    if (label.contains(query)) return 3;
    final subtitle = item.subtitle?.toLowerCase();
    if (subtitle != null && subtitle.contains(query)) return 4;
    return 5;
  }

  /// Best [_maxResults] matches, ranked. An empty query is not a search — the
  /// user is browsing, so the list stays whole.
  ///
  /// [drop] must be false for server-side results: the server matches fields
  /// this widget cannot see (phone, custom data), so a row it returned may
  /// score as "no match" here. Dropping those would hide exactly the records
  /// the search just found — they are ranked last instead.
  List<SearchableSelectItem> _rankAndLimit(
    List<SearchableSelectItem> items,
    String rawQuery, {
    required bool drop,
  }) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return items;
    final scored = <(int, SearchableSelectItem)>[];
    for (final item in items) {
      final score = _matchScore(item, query);
      if (!drop || score < 5) scored.add((score, item));
    }
    scored.sort((a, b) {
      final byScore = a.$1.compareTo(b.$1);
      // Alphabetical within a tier, so the order is stable between keystrokes
      // instead of jumping around as the source list reorders.
      return byScore != 0
          ? byScore
          : a.$2.label.toLowerCase().compareTo(b.$2.label.toLowerCase());
    });
    return [for (final entry in scored.take(_maxResults)) entry.$2];
  }

  void _onSearchChanged() {
    final onSearch = widget.onSearch;
    if (onSearch == null) {
      setState(() {
        // Local mode: this filter IS the search, so non-matches go.
        _filteredItems = _rankAndLimit(
          widget.items,
          _searchController.text,
          drop: true,
        );
      });
      return;
    }
    // Server-side mode: debounce, then fetch; keep showing current results
    // (with a progress hint) while the request is in flight.
    setState(() {}); // refresh the clear button
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final query = _searchController.text.trim();
      final seq = ++_searchSeq;
      if (mounted) setState(() => _searching = true);
      try {
        final results = query.isEmpty ? widget.items : await onSearch(query);
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          // Rank server results too: the endpoint filters, it does not order
          // by relevance. Nothing is dropped — see _rankAndLimit.
          _filteredItems = _rankAndLimit(results, query, drop: false);
          _searching = false;
        });
      } catch (_) {
        if (!mounted || seq != _searchSeq) return;
        setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height:
          MediaQuery.sizeOf(context).height * (widget.embedded ? 0.62 : 0.75),
      child: DecoratedBox(
        decoration: widget.embedded
            ? const BoxDecoration()
            : BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
        child: Column(
          children: [
            if (!widget.embedded) ...[
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withAlpha(100),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(fontSize: 18),
                    ),
                    if (widget.isNullable)
                      TextButton(
                        onPressed: () {
                          widget.onSelected(null);
                          Navigator.pop(context);
                        },
                        child: const Text('Сбросить'),
                      ),
                  ],
                ),
              ),
            ] else if (widget.isNullable)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    widget.onSelected(null);
                    Navigator.pop(context);
                  },
                  child: const Text('Сбросить'),
                ),
              ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'Очистить поиск',
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            if (_searching) const LinearProgressIndicator(minHeight: 2),

            // List
            Expanded(
              child: _filteredItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant.withAlpha(100),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Ничего не найдено',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        final isSelected = item.id == widget.selectedId;

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryGold.withAlpha(30)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected
                                ? Border.all(
                                    color: AppTheme.primaryGold.withAlpha(100),
                                  )
                                : null,
                          ),
                          child: ListTile(
                            onTap: () {
                              widget.onSelected(item);
                              Navigator.pop(context);
                            },
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primaryGold.withAlpha(
                                50,
                              ),
                              child: Text(
                                item.label.isNotEmpty
                                    ? item.label[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: AppTheme.primaryGold,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              item.label.isEmpty ? 'Без имени' : item.label,
                              style: TextStyle(
                                color: isSelected
                                    ? AppTheme.primaryGold
                                    : Theme.of(context).colorScheme.onSurface,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: item.subtitle != null
                                ? Text(
                                    item.subtitle!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  )
                                : null,
                            trailing: isSelected
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppTheme.primaryGold,
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
