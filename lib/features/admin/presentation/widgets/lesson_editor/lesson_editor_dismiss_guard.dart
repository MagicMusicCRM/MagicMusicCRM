import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface_kind.dart';

class LessonEditorDismissGuard extends StatefulWidget {
  const LessonEditorDismissGuard({
    required this.isDirty,
    required this.child,
    super.key,
  });

  final bool isDirty;
  final Widget child;

  @override
  State<LessonEditorDismissGuard> createState() =>
      _LessonEditorDismissGuardState();
}

class _LessonEditorDismissGuardState extends State<LessonEditorDismissGuard> {
  bool _allowPop = false;
  bool _confirming = false;

  Future<void> _confirmDiscard() async {
    if (_confirming) return;
    _confirming = true;
    final discard = await _showDiscardConfirmation(context);
    _confirming = false;
    if (!mounted || discard != true) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).maybePop(false);
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: _allowPop || !widget.isDirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _confirmDiscard();
    },
    child: widget.child,
  );
}

Future<bool?> _showDiscardConfirmation(BuildContext context) =>
    showMagicAdaptiveSurface<bool>(
      context,
      kind: AppSurfaceKind.confirmation,
      title: 'Отменить изменения?',
      builder: (surfaceContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Несохранённые изменения будут потеряны.'),
          const SizedBox(height: AppSpace.lg),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: AppSpace.sm,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(surfaceContext, false),
                child: const Text('Остаться'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(surfaceContext, true),
                child: const Text('Отменить изменения'),
              ),
            ],
          ),
        ],
      ),
    );
