import 'package:flutter/material.dart';

/// App-level [ScaffoldMessenger] that restores auto-dismiss for snackbars with
/// an action button.
///
/// Flutter 3.41 changed the [SnackBar] default to `persist = action != null`
/// (`snack_bar.dart`), so every «…»/«Отменить»-style snackbar in the app became
/// immortal — it ignored its `duration` entirely, and, because the messenger
/// QUEUES snackbars, every later toast (даже без кнопки) piled up behind it.
/// That is the «тосты не исчезают» bug (#16).
///
/// Mounted once in [MaterialApp.router]'s `builder` (see `main.dart`), it sits
/// between the framework's own messenger and the Navigator, so every
/// `ScaffoldMessenger.of(context)` call site in the app resolves to it — the
/// fix lives at the source, not in ~100 call sites.
///
/// A snackbar stays persistent only when explicitly requested: an actionless
/// `SnackBar(persist: true, …)` is passed through untouched. New code should
/// prefer `MagicToast` (v7) which owns its timer and never persists.
class AutoDismissScaffoldMessenger extends ScaffoldMessenger {
  const AutoDismissScaffoldMessenger({super.key, required super.child});

  @override
  ScaffoldMessengerState createState() => _AutoDismissScaffoldMessengerState();
}

class _AutoDismissScaffoldMessengerState extends ScaffoldMessengerState {
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    return super.showSnackBar(
      withSnackBarAutoDismiss(snackBar),
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
  }
}

/// Rebuilds every transient [snackBar] with the app-wide three-second duration
/// and `persist: false`. Explicit persistent actionless banners pass through.
///
/// `SnackBar.persist` is resolved at construction (`persist ?? action != null`),
/// so an explicit `persist: true` on an action snackbar is indistinguishable
/// from the framework default — action snackbars therefore always auto-dismiss.
/// Content that must stay on screen belongs in a dialog/banner, not a snackbar.
@visibleForTesting
SnackBar withSnackBarAutoDismiss(SnackBar snackBar) {
  // An explicitly persistent, actionless banner is not a toast and remains
  // untouched. Every transient snackbar — success, error and undo — follows
  // the app-wide three-second product rule.
  if (snackBar.action == null && snackBar.persist) return snackBar;
  return SnackBar(
    key: snackBar.key,
    content: snackBar.content,
    backgroundColor: snackBar.backgroundColor,
    elevation: snackBar.elevation,
    margin: snackBar.margin,
    padding: snackBar.padding,
    width: snackBar.width,
    shape: snackBar.shape,
    hitTestBehavior: snackBar.hitTestBehavior,
    behavior: snackBar.behavior,
    action: snackBar.action,
    actionOverflowThreshold: snackBar.actionOverflowThreshold,
    showCloseIcon: snackBar.showCloseIcon,
    closeIconColor: snackBar.closeIconColor,
    duration: const Duration(seconds: 3),
    persist: false,
    animation: snackBar.animation,
    onVisible: snackBar.onVisible,
    dismissDirection: snackBar.dismissDirection,
    clipBehavior: snackBar.clipBehavior,
  );
}
