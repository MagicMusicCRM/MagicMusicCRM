import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../theme/design_tokens.dart';

const magicModalDesktopBreakpoint = 840.0;

bool usesDesktopMagicModal(BuildContext context) => kIsWeb
    ? MediaQuery.sizeOf(context).width >= magicModalDesktopBreakpoint
    : switch (Theme.of(context).platform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      };

/// One route policy for action windows, including existing Dialog widgets.
Future<T?> showMagicDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  bool useSafeArea = true,
  bool showCloseButton = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
}) {
  if (!usesDesktopMagicModal(context)) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      anchorPoint: anchorPoint,
      useSafeArea: useSafeArea,
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
      isDismissible: barrierDismissible,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: AppColor.scrim,
      builder: (context) => _MobileMagicSheet(
        title: null,
        subtitle: null,
        icon: null,
        actions: null,
        embeddedDialog: true,
        showCloseButton: showCloseButton,
        body: builder(context),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: AppColor.scrim,
    useRootNavigator: useRootNavigator,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    builder: (context) => Center(
      child: ConstrainedBox(
        key: const ValueKey('magic-dialog-desktop'),
        constraints: BoxConstraints(
          maxWidth: 1000,
          maxHeight: (MediaQuery.sizeOf(context).height - 48).clamp(
            0,
            double.infinity,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          child: builder(context),
        ),
      ),
    ),
  );
}

/// Scrollable action content: centered dialog on desktop, draggable sheet on phone.
Future<T?> showMagicSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  String? subtitle,
  IconData? icon,
  List<Widget>? actions,
}) {
  if (usesDesktopMagicModal(context)) {
    return showMagicDialog<T>(
      context: context,
      useRootNavigator: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: _MagicSheetFrame(
            key: const ValueKey('magic-sheet-desktop'),
            title: title,
            subtitle: subtitle,
            icon: icon,
            actions: actions,
            body: builder(context),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: AppColor.scrim,
    builder: (context) => _MobileMagicSheet(
      title: title,
      subtitle: subtitle,
      icon: icon,
      actions: actions,
      body: builder(context),
    ),
  );
}

class _MobileMagicSheet extends StatefulWidget {
  const _MobileMagicSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    required this.body,
    this.embeddedDialog = false,
    this.showCloseButton = true,
  });

  final String? title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget>? actions;
  final Widget body;
  final bool embeddedDialog;
  final bool showCloseButton;

  @override
  State<_MobileMagicSheet> createState() => _MobileMagicSheetState();
}

class _MobileMagicSheetState extends State<_MobileMagicSheet> {
  static const _snaps = [0.58, 0.9, 1.0];
  final _controller = DraggableScrollableController();
  var _extent = _snaps.first;
  var _dismissDistance = 0.0;

  bool get _expanded => _extent >= 0.99;

  @override
  void initState() {
    super.initState();
    if (widget.embeddedDialog) _extent = _snaps[1];
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
    final availableHeight = _controller.sizeToPixels(1);
    if (availableHeight <= 0) return;
    final target = _controller.size - details.primaryDelta! / availableHeight;
    _dismissDistance = target < _snaps.first
        ? _dismissDistance + (_snaps.first - target) * availableHeight
        : 0;
    _controller.jumpTo(target.clamp(_snaps.first, _snaps.last));
  }

  void _onHandleDragEnd(DragEndDetails details) {
    if (!_controller.isAttached) return;
    final velocity = details.primaryVelocity ?? 0;
    final size = _controller.size;
    if (widget.showCloseButton &&
        size <= _snaps.first + 0.001 &&
        (_dismissDistance > 56 || velocity > 700)) {
      _dismissDistance = 0;
      Navigator.of(context).maybePop();
      return;
    }
    _dismissDistance = 0;
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
            initialChildSize: widget.embeddedDialog ? _snaps[1] : _snaps.first,
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
              label:
                  '${widget.title == null ? 'Окно' : 'Окно «${widget.title}»'}: $stateLabel',
              child: _MagicSheetFrame(
                title: widget.title,
                subtitle: widget.subtitle,
                icon: widget.icon,
                actions: widget.actions,
                body: widget.body,
                fillHeight: true,
                showHandle: true,
                embeddedDialog: widget.embeddedDialog,
                showCloseButton: widget.showCloseButton,
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
    this.showHandle = false,
    this.embeddedDialog = false,
    this.showCloseButton = true,
    super.key,
  });

  final String? title;
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
  final bool showHandle;
  final bool embeddedDialog;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    final bodyScroll = embeddedDialog
        ? CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverFillRemaining(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dialogTheme: Theme.of(context).dialogTheme.copyWith(
                      insetPadding: EdgeInsets.zero,
                      alignment: Alignment.topCenter,
                      elevation: 0,
                      shape: const RoundedRectangleBorder(),
                    ),
                  ),
                  child: MediaQuery.removeViewInsets(
                    context: context,
                    removeBottom: true,
                    child: body,
                  ),
                ),
              ),
            ],
          )
        : SingleChildScrollView(
            key: const ValueKey('magic-sheet-body-scroll'),
            controller: scrollController,
            padding: AppSpace.sheetBody,
            child: body,
          );
    return Container(
      key: const ValueKey('magic-sheet-frame'),
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColor.surface,
        border: const Border(
          top: BorderSide(color: AppColor.divider),
          left: BorderSide(color: AppColor.divider),
          right: BorderSide(color: AppColor.divider),
        ),
        borderRadius: showHandle
            ? const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))
            : BorderRadius.circular(AppRadius.sheet),
        boxShadow: AppShadow.sh2,
      ),
      child: Column(
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (showHandle)
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
                if (title != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
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
                if (title == null) const Spacer(),
                if (onToggleExtent != null)
                  IconButton(
                    key: const ValueKey('magic-sheet-toggle'),
                    onPressed: onToggleExtent,
                    tooltip: expandLabel,
                    icon: Icon(
                      expandLabel == 'Свернуть'
                          ? Icons.unfold_less_rounded
                          : Icons.unfold_more_rounded,
                    ),
                  ),
                if (showCloseButton)
                  IconButton(
                    key: const ValueKey('magic-modal-close'),
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
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
