import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/utils/ru_phone.dart';

/// Russian phone input: displays `+7 (XXX) XXX XX XX`, emits canonical
/// `+7XXXXXXXXXX` (or `''` while incomplete) via [onCanonicalChanged].
///
/// When [international] is `true` the `+7` mask and formatter are disabled:
/// the user may type any phone (e.g. `+1 202 555…`) and the raw trimmed value
/// is emitted as-is — no `+7` coercion.  The [initialCanonical] parameter is
/// used verbatim as the seed text in international mode.
class RuPhoneField extends StatefulWidget {
  const RuPhoneField({
    super.key,
    required this.onCanonicalChanged,
    this.initialCanonical,
    this.labelText = 'Телефон',
    this.decoration,
    this.international = false,
  });

  final ValueChanged<String> onCanonicalChanged;
  final String? initialCanonical;
  final String labelText;
  final InputDecoration? decoration;

  /// When `true`, disables the RU mask/formatter.  The field accepts any phone
  /// string and emits it raw (trimmed) via [onCanonicalChanged].
  final bool international;

  @override
  State<RuPhoneField> createState() => _RuPhoneFieldState();
}

class _RuPhoneFieldState extends State<RuPhoneField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.international
          ? (widget.initialCanonical ?? '')
          : canonicalToDisplay(widget.initialCanonical ?? ''),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decoration =
        widget.decoration ?? InputDecoration(labelText: widget.labelText);

    if (widget.international) {
      return TextField(
        controller: _controller,
        keyboardType: TextInputType.phone,
        decoration: decoration.copyWith(
          hintText: decoration.hintText ?? '+CC ...',
        ),
        onChanged: (text) => widget.onCanonicalChanged(text.trim()),
      );
    }

    return TextField(
      controller: _controller,
      keyboardType: TextInputType.phone,
      inputFormatters: [RuPhoneTextInputFormatter()],
      decoration: decoration,
      onChanged: (text) => widget.onCanonicalChanged(digitsToCanonical(text)),
    );
  }
}
