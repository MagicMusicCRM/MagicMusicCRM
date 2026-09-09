import 'package:flutter/material.dart';

/// Validate every mounted field and bring the first invalid input into view.
/// Layout must finish first, because error text changes the input's height.
bool validateAndRevealForm(GlobalKey<FormState> key) {
  final form = key.currentState;
  if (form == null) return true;
  final errors = form.validateGranularly();
  if (errors.isEmpty) return true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final mounted = errors.where((field) => field.mounted).toList();
    if (mounted.isEmpty) return;
    mounted.sort((a, b) => _top(a.context).compareTo(_top(b.context)));
    final target = mounted.first.context;
    EditableTextState? input;
    void visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        input ??= element.state as EditableTextState;
      }
      element.visitChildren(visit);
    }

    target.visitChildElements(visit);
    input?.widget.focusNode.requestFocus();
    _reveal(target);
  });
  return false;
}

double _top(BuildContext context) {
  final render = context.findRenderObject();
  return render is RenderBox && render.hasSize
      ? render.localToGlobal(Offset.zero).dy
      : double.infinity;
}

void _reveal(BuildContext target) {
  if (!target.mounted) return;
  Scrollable.ensureVisible(
    target,
    alignment: 0.15,
    duration: MediaQuery.disableAnimationsOf(target)
        ? Duration.zero
        : const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );
}

/// Reveal a persistent form-level explanation, including server-side failures.
void revealFormFeedback(BuildContext root, Key key) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!root.mounted) return;
    Element? target;
    void visit(Element element) {
      if (element.widget.key == key) target ??= element;
      if (target == null) element.visitChildren(visit);
    }

    root.visitChildElements(visit);
    if (target != null) _reveal(target!);
  });
}
