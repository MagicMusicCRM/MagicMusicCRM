import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'choice_dropdown.dart';

String _label(Widget? widget) {
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  }
  if (widget is RichText) return widget.text.toPlainText();
  if (widget is Flex) {
    return widget.children.map(_label).where((v) => v.isNotEmpty).join(' ');
  }
  if (widget is SingleChildRenderObjectWidget) return _label(widget.child);
  if (widget is Container) return _label(widget.child);
  if (widget is DefaultTextStyle) return _label(widget.child);
  return '';
}

/// Drop-in adapter for existing typed choices. Nullable option values are mapped
/// by index so that selecting "all" remains distinct from dismissing the menu.
class AppDropdownButton<T> extends StatelessWidget {
  const AppDropdownButton({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.hint,
    this.disabledHint,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.onTap,
    this.menuMaxHeight,
    this.decoration,
    this.isExpanded = false,
    this.isDense = false,
    this.icon,
    this.iconSize = 24,
    this.iconEnabledColor,
    this.iconDisabledColor,
    this.dropdownColor,
    this.focusColor,
    this.elevation = 8,
    this.itemHeight = kMinInteractiveDimension,
    this.borderRadius,
    this.alignment = AlignmentDirectional.centerStart,
    this.padding,
    this.enableFeedback,
    this.selectedItemBuilder,
    this.underline,
    this.menuWidth,
    this.barrierDismissible = true,
  });
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final T? value;
  final Widget? hint, disabledHint, icon, underline;
  final TextStyle? style;
  final FocusNode? focusNode;
  final bool autofocus, isExpanded, isDense, barrierDismissible;
  final VoidCallback? onTap;
  final double? menuMaxHeight, itemHeight, menuWidth;
  final double iconSize;
  final Color? iconEnabledColor, iconDisabledColor, dropdownColor, focusColor;
  final int elevation;
  final BorderRadius? borderRadius;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry? padding;
  final bool? enableFeedback;
  final DropdownButtonBuilder? selectedItemBuilder;
  final InputDecoration? decoration;
  @override
  Widget build(BuildContext context) {
    final options = items ?? <DropdownMenuItem<T>>[];
    final index = options.indexWhere((item) => item.value == value);
    final dropdown = ChoiceDropdown(
      labels: {
        for (var i = 0; i < options.length; i++) '$i': _label(options[i].child),
      },
      optionWidgets: {
        for (var i = 0; i < options.length; i++) '$i': options[i].child,
      },
      disabledOptions: {
        for (var i = 0; i < options.length; i++)
          if (!options[i].enabled) '$i',
      },
      selected: {if (index >= 0) '$index'},
      enabled: onChanged != null && options.isNotEmpty,
      emptyLabel: _label(onChanged == null ? disabledHint ?? hint : hint),
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap,
      menuMaxHeight: menuMaxHeight ?? 280,
      decoration: decoration ?? InputDecoration(isDense: isDense),
      onChanged: (keys) {
        if (keys.isEmpty) return;
        final item = options[int.parse(keys.single)];
        item.onTap?.call();
        onChanged?.call(item.value);
      },
    );
    if (isExpanded || decoration != null) return dropdown;
    final label = TextPainter(
      text: TextSpan(
        text: index >= 0 ? _label(options[index].child) : _label(hint),
        style: style ?? Theme.of(context).textTheme.bodyLarge,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final preferredWidth = (label.width + 64).clamp(120.0, 260.0);
    label.dispose();
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.hasBoundedWidth
            ? math.min(preferredWidth, constraints.maxWidth * 0.6)
            : preferredWidth,
        child: dropdown,
      ),
    );
  }
}

/// Keeps Form validation, saving, reset and nullable choices in the existing
/// forms while replacing only the field/menu presentation.
class AppDropdownButtonFormField<T> extends FormField<T> {
  final ValueChanged<T?>? onChanged;
  AppDropdownButtonFormField({
    super.key,
    required List<DropdownMenuItem<T>>? items,
    this.onChanged,
    T? value,
    T? initialValue,
    InputDecoration decoration = const InputDecoration(),
    super.onSaved,
    super.validator,
    super.autovalidateMode,
    super.restorationId,
    super.forceErrorText,
    super.errorBuilder,
    super.onReset,
    Widget? hint,
    Widget? disabledHint,
    TextStyle? style,
    FocusNode? focusNode,
    bool autofocus = false,
    VoidCallback? onTap,
    double? menuMaxHeight,
    bool isExpanded = false,
    bool isDense = true,
    Widget? icon,
    double iconSize = 24,
    Color? iconEnabledColor,
    Color? iconDisabledColor,
    Color? dropdownColor,
    Color? focusColor,
    int elevation = 8,
    double? itemHeight = kMinInteractiveDimension,
    BorderRadius? borderRadius,
    AlignmentGeometry alignment = AlignmentDirectional.centerStart,
    EdgeInsetsGeometry? padding,
    bool? enableFeedback,
    DropdownButtonBuilder? selectedItemBuilder,
    bool barrierDismissible = true,
  }) : super(
         initialValue: initialValue ?? value,
         enabled: onChanged != null,
         builder: (field) => AppDropdownButton<T>(
           items: items,
           value: field.value,
           onChanged: onChanged == null
               ? null
               : (value) {
                   field.didChange(value);
                   onChanged(value);
                 },
           decoration: decoration.copyWith(
             errorText: field.errorText ?? decoration.errorText,
           ),
           hint: hint,
           disabledHint: disabledHint,
           style: style,
           focusNode: focusNode,
           autofocus: autofocus,
           onTap: onTap,
           menuMaxHeight: menuMaxHeight,
           isExpanded: isExpanded,
           isDense: isDense,
           selectedItemBuilder: selectedItemBuilder,
         ),
       );
  @override
  FormFieldState<T> createState() => _AppDropdownFormFieldState<T>();
}

class _AppDropdownFormFieldState<T> extends FormFieldState<T> {
  @override
  void didUpdateWidget(covariant AppDropdownButtonFormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }
}
