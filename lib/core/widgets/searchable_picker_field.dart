import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';

/// A form field that opens [SearchableSelect] instead of a dropdown.
///
/// Long, data-driven lists (teachers, students, rooms, groups) do not belong in
/// a dropdown: the pre-loaded page is capped, so the record you want may not
/// even be in the list, and scrolling past a hundred names is slower than
/// typing three letters. Use a plain dropdown for short fixed sets (statuses,
/// weekdays) — this widget is for the unbounded ones.
class SearchablePickerField extends StatelessWidget {
  final String label;

  /// Text shown when nothing is picked yet.
  final String placeholder;
  final String hintText;
  final String? selectedId;
  final String? selectedLabel;
  final List<SearchableSelectItem> items;
  final ValueChanged<SearchableSelectItem?> onSelected;

  /// Server-side search for lists too large to preload; see [SearchableSelect].
  final Future<List<SearchableSelectItem>> Function(String query)? onSearch;
  final bool isNullable;
  final bool enabled;

  const SearchablePickerField({
    super.key,
    required this.label,
    required this.items,
    required this.onSelected,
    this.placeholder = 'Не выбрано',
    this.hintText = 'Начните вводить…',
    this.selectedId,
    this.selectedLabel,
    this.onSearch,
    this.isNullable = true,
    this.enabled = true,
  });

  /// Falls back to the matching item's label so callers that only track an id
  /// do not have to mirror the display name in their own state.
  String? get _resolvedLabel {
    if (selectedLabel != null) return selectedLabel;
    for (final item in items) {
      if (item.id == selectedId) return item.label;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final shown = _resolvedLabel;
    return InkWell(
      onTap: enabled
          ? () => SearchableSelect.show(
              context: context,
              title: label,
              hintText: hintText,
              items: items,
              selectedId: selectedId,
              isNullable: isNullable,
              onSearch: onSearch,
              onSelected: onSelected,
            )
          : null,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, enabled: enabled),
        child: Row(
          children: [
            Expanded(
              child: Text(
                shown ?? placeholder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: shown == null
                    ? TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )
                    : null,
              ),
            ),
            const Icon(Icons.search_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
