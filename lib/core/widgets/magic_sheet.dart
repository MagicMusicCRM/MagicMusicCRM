import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// Opens a v7 bottom sheet (`.sheet` — grabber, head with icon-badge +
/// title/subtitle, scrollable body, optional footer actions) and resolves to
/// whatever the body pops via `Navigator.pop`.
///
/// Mirrors the prototype's booking / expense / card-menu sheets. Additive in
/// P0 — the canonical wrapper reskin phases use instead of bespoke
/// `showModalBottomSheet` chrome.
Future<T?> showMagicSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  String? subtitle,
  IconData? icon,
  List<Widget>? actions,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: AppColor.scrim,
    builder: (context) => _MagicSheet(
      title: title,
      subtitle: subtitle,
      icon: icon,
      actions: actions,
      body: builder(context),
    ),
  );
}

class _MagicSheet extends StatelessWidget {
  const _MagicSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    required this.body,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget>? actions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width < 840) {
      return _MobileMagicSheet(
        title: title,
        subtitle: subtitle,
        icon: icon,
        actions: actions,
        body: body,
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 460,
              maxHeight: media.size.height * 0.9,
            ),
            child: _MagicSheetFrame(
              key: const ValueKey('magic-sheet-desktop'),
              title: title,
              subtitle: subtitle,
              icon: icon,
              actions: actions,
              body: body,
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileMagicSheet extends StatefulWidget {
  const _MobileMagicSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    required this.body,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget>? actions;
  final Widget body;

  @override
  State<_MobileMagicSheet> createState() => _MobileMagicSheetState();
}

class _MobileMagicSheetState extends State<_MobileMagicSheet> {
  static const _snaps = [0.58, 0.9, 1.0];
  final _controller = DraggableScrollableController();
  var _extent = _snaps.first;

  bool get _expanded => _extent >= 0.99;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncExtent);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncExtent);
    _controller.dispose();
    super.dispose();
  }

  void _syncExtent() {
    if (!mounted || !_controller.isAttached) return;
    final next = _controller.size;
    if ((next - _extent).abs() < 0.001) return;
    setState(() => _extent = next);
  }

  void _toggleExtent() {
    _animateTo(_expanded ? _snaps.first : _snaps.last);
  }

  void _onHandleDragUpdate(DragUpdateDetails details) {
    if (!_controller.isAttached || details.primaryDelta == null) return;
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height - media.viewInsets.bottom - media.padding.vertical;
    if (availableHeight <= 0) return;
    _controller.jumpTo(
      (_controller.size - details.primaryDelta! / availableHeight).clamp(
        _snaps.first,
        _snaps.last,
      ),
    );
  }

  void _onHandleDragEnd(DragEndDetails details) {
    if (!_controller.isAttached) return;
    final velocity = details.primaryVelocity ?? 0;
    final size = _controller.size;
    double target;
    if (velocity < -200) {
      target = _snaps.firstWhere((snap) => snap > size, orElse: () => 1);
    } else if (velocity > 200) {
      target = _snaps.lastWhere(
        (snap) => snap < size,
        orElse: () => _snaps.first,
      );
    } else {
      target = _snaps.reduce(
        (left, right) =>
            (left - size).abs() <= (right - size).abs() ? left : right,
      );
    }
    _animateTo(target);
  }

  void _animateTo(double target) async {
    if (!_controller.isAttached) return;
    final duration = AppMotion.effective(context, AppMotion.medium);
    if (duration == Duration.zero) {
      _controller.jumpTo(target);
      return;
    }
    await _controller.animateTo(
      target,
      duration: duration,
      curve: AppMotion.ease,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final stateLabel = _expanded ? 'развернуто' : 'частично развернуто';
    return AnimatedPadding(
      duration: AppMotion.effective(context, AppMotion.medium),
      curve: AppMotion.ease,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: DraggableScrollableSheet(
            key: const ValueKey('magic-sheet-mobile'),
            controller: _controller,
            initialChildSize: _snaps.first,
            minChildSize: _snaps.first,
            maxChildSize: _snaps.last,
            snap: true,
            snapSizes: _snaps,
            shouldCloseOnMinExtent: false,
            expand: false,
            builder: (context, scrollController) => Semantics(
              key: const ValueKey('magic-sheet-state'),
              container: true,
              liveRegion: true,
              label: 'Окно «${widget.title}»: $stateLabel',
              child: _MagicSheetFrame(
                title: widget.title,
                subtitle: widget.subtitle,
                icon: widget.icon,
                actions: widget.actions,
                body: widget.body,
                fillHeight: true,
                scrollController: scrollController,
                expandLabel: _expanded ? 'Свернуть' : 'Развернуть',
                onToggleExtent: _toggleExtent,
                onHandleDragUpdate: _onHandleDragUpdate,
                onHandleDragEnd: _onHandleDragEnd,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MagicSheetFrame extends StatelessWidget {
  const _MagicSheetFrame({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    required this.body,
    this.fillHeight = false,
    this.scrollController,
    this.expandLabel,
    this.onToggleExtent,
    this.onHandleDragUpdate,
    this.onHandleDragEnd,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget>? actions;
  final Widget body;
  final bool fillHeight;
  final ScrollController? scrollController;
  final String? expandLabel;
  final VoidCallback? onToggleExtent;
  final GestureDragUpdateCallback? onHandleDragUpdate;
  final GestureDragEndCallback? onHandleDragEnd;

  @override
  Widget build(BuildContext context) {
    final bodyScroll = SingleChildScrollView(
      key: const ValueKey('magic-sheet-body-scroll'),
      controller: scrollController,
      padding: AppSpace.sheetBody,
      child: body,
    );
    return Container(
      key: const ValueKey('magic-sheet-frame'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColor.surface,
        border: const Border(
          top: BorderSide(color: AppColor.divider),
          left: BorderSide(color: AppColor.divider),
          right: BorderSide(color: AppColor.divider),
        ),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        boxShadow: AppShadow.sh2,
      ),
      child: Column(
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          GestureDetector(
            key: const ValueKey('magic-sheet-handle'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: onHandleDragUpdate,
            onVerticalDragEnd: onHandleDragEnd,
            child: SizedBox(
              height: 16,
              width: double.infinity,
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColor.sheetGrab,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 12, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColor.goldSoft,
                      borderRadius: BorderRadius.circular(AppRadius.icon),
                      border: Border.all(color: AppColor.goldLine),
                    ),
                    child: Icon(icon, size: 20, color: AppColor.gold),
                  ),
                  const SizedBox(width: AppSpace.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColor.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColor.text2,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (onToggleExtent != null)
                  TextButton(
                    key: const ValueKey('magic-sheet-toggle'),
                    onPressed: onToggleExtent,
                    child: Text(expandLabel!),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColor.divider),
          if (fillHeight)
            Expanded(child: bodyScroll)
          else
            Flexible(child: bodyScroll),
          if (actions != null && actions!.isNotEmpty) ...[
            const Divider(height: 1, color: AppColor.divider),
            Padding(
              key: const ValueKey('magic-sheet-footer'),
              padding: const EdgeInsets.fromLTRB(20, 13, 20, 18),
              child: Row(
                children: [
                  for (var i = 0; i < actions!.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpace.sm),
                    Expanded(child: actions![i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
