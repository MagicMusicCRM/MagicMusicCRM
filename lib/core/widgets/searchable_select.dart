import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

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

  const SearchableSelect({
    super.key,
    required this.title,
    required this.hintText,
    required this.items,
    required this.onSelected,
    this.selectedId,
    this.isNullable = true,
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
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SearchableSelect(
        title: title,
        hintText: hintText,
        items: items,
        onSelected: onSelected,
        selectedId: selectedId,
        isNullable: isNullable,
      ),
    );
  }
}

class _SearchableSelectState extends State<SearchableSelect> {
  final TextEditingController _searchController = TextEditingController();
  List<SearchableSelectItem> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = widget.items.where((item) {
        return item.label.toLowerCase().contains(query) ||
            (item.subtitle?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(100),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 18),
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

          // List
          Expanded(
            child: _filteredItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(100)),
                        const SizedBox(height: 16),
                        Text('Ничего не найдено', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      final isSelected = item.id == widget.selectedId;

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryPurple.withAlpha(30) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected 
                            ? Border.all(color: AppTheme.primaryPurple.withAlpha(100))
                            : null,
                        ),
                        child: ListTile(
                          onTap: () {
                            widget.onSelected(item);
                            Navigator.pop(context);
                          },
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryPurple.withAlpha(50),
                            child: Text(
                              item.label.isNotEmpty ? item.label[0].toUpperCase() : '?',
                              style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            item.label.isEmpty ? 'Без имени' : item.label,
                            style: TextStyle(
                              color: isSelected ? AppTheme.primaryPurple : Theme.of(context).colorScheme.onSurface,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: item.subtitle != null 
                              ? Text(item.subtitle!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))
                              : null,
                          trailing: isSelected 
                              ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryPurple)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
