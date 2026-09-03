import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

/// Compact searchable field for data-driven lists such as people and rooms.
///
/// The native menu stays anchored under the field, shows at most five rows,
/// and supplies its own always-visible desktop scrollbar. Fixed short sets
/// (statuses, weekdays) should keep using a plain dropdown.
class SearchablePickerField extends StatefulWidget {
  final String label;

  /// Text shown when nothing is picked yet.
  final String placeholder;
  final String hintText;
  final String? selectedId;
  final String? selectedLabel;
  final String? errorText;
  final List<SearchableSelectItem> items;
  final ValueChanged<SearchableSelectItem?> onSelected;

  /// Server-side search for lists too large to preload.
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
    this.errorText,
    this.onSearch,
    this.isNullable = true,
    this.enabled = true,
  });

  @override
  State<SearchablePickerField> createState() => _SearchablePickerFieldState();
}

class _SearchablePickerFieldState extends State<SearchablePickerField> {
  static const _menuHeight = 5 * 48.0 + 16.0;
  static const _clearId = '__clear_searchable_picker__';

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _menuController = MenuController();
  Timer? _debounce;
  List<SearchableSelectItem> _items = const [];
  int _searchSequence = 0;
  int _menuRevision = 0;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _items = widget.items;
    _syncSelection();
    _controller.addListener(_search);
    _focusNode.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant SearchablePickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _debounce?.cancel();
      _searchSequence++;
      _searching = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.enabled) _menuController.close();
      });
    }
    if (!_sameItems(oldWidget.items, widget.items) && !_searching) {
      _items = widget.items;
    }
    if (oldWidget.selectedId != widget.selectedId ||
        oldWidget.selectedLabel != widget.selectedLabel) {
      _syncSelection();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String? get _selectedLabel {
    if (widget.selectedLabel != null) return widget.selectedLabel;
    for (final item in widget.items) {
      if (item.id == widget.selectedId) return item.label;
    }
    return null;
  }

  bool _sameItems(
    List<SearchableSelectItem> left,
    List<SearchableSelectItem> right,
  ) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.id != b.id ||
          a.label != b.label ||
          a.subtitle != b.subtitle ||
          a.avatarUrl != b.avatarUrl ||
          !mapEquals(a.data, b.data)) {
        return false;
      }
    }
    return true;
  }

  void _syncSelection() {
    _debounce?.cancel();
    _searchSequence++;
    final text = _selectedLabel ?? '';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _handleFocus() {
    if (_focusNode.hasFocus) {
      final selected = _selectedLabel;
      if (selected != null && _controller.text == selected) {
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: selected.length,
        );
      }
      return;
    }
    if (_controller.text != (_selectedLabel ?? '')) _syncSelection();
  }

  void _search() {
    if (!widget.enabled) return;
    final search = widget.onSearch;
    if (search == null) return;
    final query = _controller.text.trim();
    if (query == _selectedLabel) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted || !widget.enabled) return;
      final sequence = ++_searchSequence;
      if (mounted) setState(() => _searching = true);
      try {
        final items = query.isEmpty ? widget.items : await search(query);
        if (!mounted || !widget.enabled || sequence != _searchSequence) return;
        setState(() {
          _items = items;
          _menuRevision++;
          _searching = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              !widget.enabled ||
              sequence != _searchSequence ||
              _controller.text.trim() != query) {
            return;
          }
          _menuController.open();
        });
      } catch (_) {
        if (mounted && sequence == _searchSequence) {
          setState(() => _searching = false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => DropdownMenu<String>(
        key: ValueKey('searchable-picker-${widget.selectedId}-$_menuRevision'),
        controller: _controller,
        focusNode: _focusNode,
        menuController: _menuController,
        width: constraints.maxWidth,
        menuHeight: _menuHeight,
        enabled: widget.enabled,
        enableFilter: true,
        enableSearch: true,
        requestFocusOnTap: true,
        label: Text(widget.label),
        hintText: widget.placeholder,
        helperText: widget.hintText,
        errorText: widget.errorText,
        leadingIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : const Icon(Icons.search_rounded),
        dropdownMenuEntries: [
          for (final item in _items)
            DropdownMenuEntry<String>(
              value: item.id,
              label: item.label,
              labelWidget: item.subtitle == null
                  ? null
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label, overflow: TextOverflow.ellipsis),
                        Text(
                          item.subtitle!,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
            ),
          if (widget.isNullable && widget.selectedId != null)
            const DropdownMenuEntry<String>(
              value: _clearId,
              label: 'Сбросить выбор',
              leadingIcon: Icon(Icons.clear_rounded),
            ),
        ],
        filterCallback: widget.onSearch == null
            ? null
            : (entries, _) => entries,
        onSelected: (id) {
          if (!widget.enabled || id == null) return;
          _debounce?.cancel();
          if (id == _clearId) {
            _controller.clear();
            widget.onSelected(null);
            return;
          }
          final item = _items.where((item) => item.id == id).firstOrNull;
          if (item != null) widget.onSelected(item);
        },
      ),
    );
  }
}
