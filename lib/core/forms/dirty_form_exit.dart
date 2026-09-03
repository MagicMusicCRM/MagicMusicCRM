import 'dart:async';

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';

enum DirtyFormExitReason {
  appBack,
  systemBack,
  breadcrumb,
  tabSwitch,
  tabClose,
  logout,
}

enum DirtyFormExitDecision { save, discard, cancel }

typedef DirtyFormSave = Future<bool> Function();

Future<DirtyFormExitDecision?> showDirtyFormExitDialog(BuildContext context) {
  return showMagicDialog<DirtyFormExitDecision>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Сохранить изменения?'),
      content: const Text(
        'В форме есть несохранённые данные. Выберите, что сделать перед выходом.',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(dialogContext, DirtyFormExitDecision.cancel),
          child: const Text('Остаться'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(dialogContext, DirtyFormExitDecision.discard),
          child: const Text('Не сохранять'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(dialogContext, DirtyFormExitDecision.save),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
}

class DirtyFormExitController extends ChangeNotifier {
  DirtyFormExitController({required this.onSave, this.onDiscard});

  final DirtyFormSave onSave;
  final VoidCallback? onDiscard;

  bool _dirty = false;
  bool _busy = false;
  bool _resolving = false;

  bool get dirty => _dirty;
  bool get busy => _busy;

  void markDirty() {
    if (_dirty) return;
    _dirty = true;
    notifyListeners();
  }

  void markClean() {
    if (!_dirty) return;
    _dirty = false;
    notifyListeners();
  }

  void setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }

  Future<bool> requestExit(
    BuildContext context, {
    required DirtyFormExitReason reason,
    Object? savedResult,
    Object? discardedResult,
  }) async {
    if (_busy || _resolving) return false;
    if (!_dirty) {
      Navigator.of(context).pop(discardedResult);
      return true;
    }

    _resolving = true;
    DirtyFormExitDecision? decision;
    var canExit = false;
    try {
      decision = await showDirtyFormExitDialog(context);
      switch (decision) {
        case DirtyFormExitDecision.save:
          canExit = await onSave();
          if (canExit) markClean();
          break;
        case DirtyFormExitDecision.discard:
          onDiscard?.call();
          markClean();
          canExit = true;
          break;
        case DirtyFormExitDecision.cancel:
        case null:
          break;
      }
    } finally {
      _resolving = false;
    }
    if (canExit && context.mounted) {
      Navigator.of(context).pop(
        decision == DirtyFormExitDecision.save ? savedResult : discardedResult,
      );
    }
    return canExit;
  }
}

class DirtyFormExitScope extends StatelessWidget {
  const DirtyFormExitScope({
    required this.controller,
    required this.child,
    this.savedResult,
    this.discardedResult,
    super.key,
  });

  final DirtyFormExitController controller;
  final Widget child;
  final Object? savedResult;
  final Object? discardedResult;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => PopScope(
        canPop: !controller.dirty && !controller.busy,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          unawaited(
            controller.requestExit(
              context,
              reason: DirtyFormExitReason.systemBack,
              savedResult: savedResult,
              discardedResult: discardedResult,
            ),
          );
        },
        child: child,
      ),
    );
  }
}
