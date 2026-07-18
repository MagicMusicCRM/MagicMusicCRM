import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// Semantic toast kinds → icon + tinted icon badge (v7 `.toast .t-ic`).
enum MagicToastType { success, danger, info }

/// v7 toast (`.toast` — floating `#202024` pill, bottom-center, optional undo
/// action). Overlay-based, so it works with or without a [Scaffold] and stacks
/// above sheets/drawers (`--z-toast`).
///
/// This is the canonical replacement for the ~100 ad-hoc
/// `ScaffoldMessenger.showSnackBar` call sites; reskin phases migrate onto it.
///
/// Auto-dismiss is guaranteed by an own [Timer] — it never depends on
/// `SnackBar.persist` semantics. Danger toasts get a little more reading time
/// and can also be dismissed by tap (крестик/по самому тосту) — #16.
class MagicToast {
  MagicToast._();

  static OverlayEntry? _current;
  static Timer? _timer;

  /// Default lifetime of success/info toasts (#16 — «~3 секунды и исчез»).
  static const Duration defaultDuration = Duration(seconds: 3);

  /// Errors follow the same product rule as every transient notification:
  /// exactly three seconds, with tap-to-dismiss still available.
  static const Duration dangerDuration = Duration(seconds: 3);

  /// Shows [message] (with optional secondary [detail]) as a toast. If
  /// [actionLabel]/[onAction] are given, renders a trailing gold action
  /// (e.g. «Отменить» for undo). Auto-dismisses after [duration]
  /// ([defaultDuration] by default; [dangerDuration] for danger toasts).
  static void show(
    BuildContext context,
    String message, {
    String? detail,
    MagicToastType type = MagicToastType.info,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    dismiss();

    final entry = OverlayEntry(
      builder: (context) => _ToastHost(
        message: message,
        detail: detail,
        type: type,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                dismiss();
                onAction();
              },
        onDismissTap: type == MagicToastType.danger ? dismiss : null,
      ),
    );
    _current = entry;
    overlay.insert(entry);
    _timer = Timer(
      duration ??
          (type == MagicToastType.danger ? dangerDuration : defaultDuration),
      dismiss,
    );
  }

  /// Removes the visible toast immediately, if any. Never throws — a toast
  /// whose overlay is already gone (route disposed) must not wedge the next
  /// [show] call.
  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    try {
      _current?.remove();
      _current?.dispose();
    } catch (_) {
      // Entry already removed/disposed with its overlay — nothing to clean.
    } finally {
      _current = null;
    }
  }
}

class _ToastHost extends StatefulWidget {
  const _ToastHost({
    required this.message,
    required this.detail,
    required this.type,
    required this.actionLabel,
    required this.onAction,
    required this.onDismissTap,
  });

  final String message;
  final String? detail;
  final MagicToastType type;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Non-null → the toast is manually dismissible: tap anywhere on the pill
  /// (and the trailing ✕) closes it. Used for danger toasts (#16).
  final VoidCallback? onDismissTap;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.fast,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  (IconData, Color) get _iconSpec {
    switch (widget.type) {
      case MagicToastType.success:
        return (Icons.check_rounded, AppColor.success);
      case MagicToastType.danger:
        return (Icons.error_outline_rounded, AppColor.danger);
      case MagicToastType.info:
        return (Icons.info_outline_rounded, AppColor.gold);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, accent) = _iconSpec;
    final curved = CurvedAnimation(parent: _controller, curve: AppMotion.ease);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 78,
      child: IgnorePointer(
        ignoring: widget.onAction == null && widget.onDismissTap == null,
        child: Center(
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.4),
                end: Offset.zero,
              ).animate(curved),
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  behavior: widget.onDismissTap == null
                      ? HitTestBehavior.deferToChild
                      : HitTestBehavior.opaque,
                  onTap: widget.onDismissTap,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColor.overlay,
                      borderRadius: BorderRadius.circular(AppRadius.overlay),
                      border: Border.all(color: AppColor.divider),
                      boxShadow: AppShadow.sh2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                          ),
                          child: Icon(icon, size: 18, color: accent),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.message,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColor.text,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (widget.detail != null)
                                Text(
                                  widget.detail!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColor.text2,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (widget.actionLabel != null &&
                            widget.onAction != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: TextButton(
                              onPressed: widget.onAction,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColor.gold,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.chip,
                                  ),
                                ),
                              ),
                              child: Text(
                                widget.actionLabel!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        if (widget.onDismissTap != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: InkWell(
                              onTap: widget.onDismissTap,
                              borderRadius: BorderRadius.circular(
                                AppRadius.chip,
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: AppColor.text2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
