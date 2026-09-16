import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// Search stays in the anchor; the options never cover the editable field.
class ChoiceDropdown extends StatefulWidget {
  const ChoiceDropdown({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.multiple = false,
    this.decoration = const InputDecoration(),
    this.enabled = true,
    this.optionWidgets = const {},
    this.disabledOptions = const {},
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.onTap,
    this.menuMaxHeight = 280,
    this.emptyLabel = 'Все',
  });
  final Map<String, String> labels;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool multiple, enabled, autofocus;
  final InputDecoration decoration;
  final Map<String, Widget> optionWidgets;
  final Set<String> disabledOptions;
  final FocusNode? focusNode;
  final TextStyle? style;
  final VoidCallback? onTap;
  final double menuMaxHeight;
  final String emptyLabel;
  @override
  State<ChoiceDropdown> createState() => _ChoiceDropdownState();
}

class _ChoiceDropdownState extends State<ChoiceDropdown> {
  final _menu = MenuController();
  final _text = TextEditingController();
  final _anchor = GlobalKey();
  final _ownedFocus = FocusNode();
  String _query = '';
  bool _above = false;
  bool _opening = false;
  VoidCallback? _cancelScrollWait;
  double _height = 280;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  String get _summary => widget.selected.isEmpty
      ? widget.emptyLabel
      : widget.selected.length == 1
      ? widget.labels[widget.selected.first] ?? widget.emptyLabel
      : 'Выбрано: ${widget.selected.length}';
  @override
  void initState() {
    super.initState();
    _text.text = _summary;
  }

  @override
  void didUpdateWidget(covariant ChoiceDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_menu.isOpen) _text.text = _summary;
    if (!widget.enabled && _menu.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _menu.close();
      });
    }
  }

  @override
  void dispose() {
    _cancelScrollWait?.call();
    _text.dispose();
    _ownedFocus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (!widget.enabled || _opening) return;
    _opening = true;
    widget.onTap?.call();
    _query = '';
    _text.clear();
    _focus.requestFocus();
    // EditableText may reveal its caret by scrolling a containing sheet.
    // Native menus close on scroll, so wait for that reveal before opening.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final scrolling = Scrollable.maybeOf(context)?.position.isScrollingNotifier;
    if (scrolling != null && scrolling.value) {
      final idle = Completer<void>();
      void changed() {
        if (!scrolling.value) _cancelScrollWait?.call();
      }

      _cancelScrollWait = () {
        scrolling.removeListener(changed);
        if (!idle.isCompleted) idle.complete();
        _cancelScrollWait = null;
      };
      scrolling.addListener(changed);
      await idle.future;
    }
    if (!mounted) return;
    _opening = false;
    if (!widget.enabled || !_focus.hasFocus) return;
    final box = _anchor.currentContext!.findRenderObject()! as RenderBox;
    final top = box.localToGlobal(Offset.zero).dy;
    final media = MediaQuery.of(context);
    final below =
        media.size.height -
        media.viewInsets.bottom -
        media.padding.bottom -
        top -
        box.size.height -
        12;
    final above = top - media.padding.top - 12;
    setState(() {
      _above = below < 160 && above > below;
      _height = math.max(
        48,
        math.min(widget.menuMaxHeight, _above ? above : below),
      );
    });
    _menu.open();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.hasBoundedWidth ? constraints.maxWidth : 240.0;
      final entries = widget.labels.entries
          .where((e) => e.value.toLowerCase().contains(_query.toLowerCase()))
          .toList();
      final rows = entries.length + (widget.multiple ? 1 : 0);
      final height = math.min(_height, math.max(1, rows) * 48.0 + 16);
      return SizedBox(
        width: width,
        child: MenuAnchor(
          controller: _menu,
          childFocusNode: _focus,
          consumeOutsideTap: false,
          onClose: () {
            if (mounted) {
              setState(() {
                _query = '';
                _text.text = _summary;
              });
            }
          },
          alignmentOffset: Offset(0, _above ? -height - 6 : 6),
          style: MenuStyle(
            visualDensity: VisualDensity.standard,
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: const WidgetStatePropertyAll(AppColor.surface),
            alignment: _above ? Alignment.topLeft : Alignment.bottomLeft,
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(Size(width, height)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            side: const WidgetStatePropertyAll(
              BorderSide(color: AppColor.borderSoft),
            ),
          ),
          menuChildren: [
            if (widget.multiple)
              SizedBox(
                width: width - 16,
                height: 48,
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          widget.onChanged({});
                          if (mounted) setState(() {});
                        },
                        child: const Text(
                          'Сбросить выбор',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _menu.close,
                      child: const Text('Готово'),
                    ),
                  ],
                ),
              ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Ничего не найдено'),
              ),
            for (final entry in entries)
              MenuItemButton(
                key: ValueKey('type-filter-${entry.key}'),
                // Closing the native menu tree also closes a containing filter
                // popover. Only this field owns the close action.
                closeOnActivate: false,
                onPressed: widget.disabledOptions.contains(entry.key)
                    ? null
                    : () {
                        if (!mounted) return;
                        final next = widget.multiple
                            ? {...widget.selected}
                            : <String>{};
                        if (!next.remove(entry.key)) next.add(entry.key);
                        widget.onChanged(next);
                        if (!mounted) return;
                        if (!widget.multiple) _menu.close();
                        setState(() {});
                      },
                leadingIcon: widget.multiple
                    ? Icon(
                        widget.selected.contains(entry.key)
                            ? Icons.check_box_outlined
                            : Icons.check_box_outline_blank,
                        size: 20,
                      )
                    : null,
                trailingIcon:
                    !widget.multiple && widget.selected.contains(entry.key)
                    ? const Icon(Icons.check, size: 18)
                    : null,
                child: SizedBox(
                  width: math.max(32, width - 96),
                  child:
                      widget.optionWidgets[entry.key] ??
                      Text(
                        entry.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                ),
              ),
          ],
          builder: (context, controller, child) => TextField(
            key: _anchor,
            controller: _text,
            focusNode: _focus,
            scrollPadding: EdgeInsets.zero,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            style: widget.style,
            onTap: () {
              if (!_menu.isOpen) _open();
            },
            onChanged: (query) {
              if (!_menu.isOpen) {
                _open();
                _text.value = TextEditingValue(
                  text: query,
                  selection: TextSelection.collapsed(offset: query.length),
                );
              }
              setState(() => _query = query);
            },
            onSubmitted: (_) {
              final match = entries
                  .where((entry) => !widget.disabledOptions.contains(entry.key))
                  .firstOrNull;
              if (match == null) return;
              final next = widget.multiple ? {...widget.selected} : <String>{};
              if (!next.remove(match.key)) next.add(match.key);
              widget.onChanged(next);
              if (mounted && !widget.multiple) _menu.close();
            },
            decoration: widget.decoration.copyWith(
              hintText: _menu.isOpen ? 'Введите для поиска' : widget.emptyLabel,
              suffixIcon: IconButton(
                tooltip: _menu.isOpen ? 'Закрыть список' : 'Открыть список',
                onPressed: widget.enabled
                    ? () => _menu.isOpen ? _menu.close() : _open()
                    : null,
                icon: Icon(
                  _menu.isOpen ? Icons.expand_less : Icons.expand_more,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
