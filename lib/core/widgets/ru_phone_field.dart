import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/utils/ru_phone.dart';

/// Russian phone input: displays `+7 (XXX) XXX XX XX`, emits canonical
/// `+7XXXXXXXXXX` (or `''` while incomplete) via [onCanonicalChanged].
class RuPhoneField extends StatefulWidget {
  const RuPhoneField({
    super.key,
    required this.onCanonicalChanged,
    this.initialCanonical,
    this.labelText = 'Телефон',
    this.decoration,
  });

  final ValueChanged<String> onCanonicalChanged;
  final String? initialCanonical;
  final String labelText;
  final InputDecoration? decoration;

  @override
  State<RuPhoneField> createState() => _RuPhoneFieldState();
}

class _RuPhoneFieldState extends State<RuPhoneField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: canonicalToDisplay(widget.initialCanonical ?? ''),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.phone,
      inputFormatters: [RuPhoneTextInputFormatter()],
      decoration:
          widget.decoration ?? InputDecoration(labelText: widget.labelText),
      onChanged: (text) => widget.onCanonicalChanged(digitsToCanonical(text)),
    );
  }
}
