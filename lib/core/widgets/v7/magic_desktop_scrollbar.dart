import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

typedef MagicScrollableBuilder =
    Widget Function(BuildContext context, ScrollController controller);

/// Owns exactly one scroll controller and exposes a persistent draggable
/// scrollbar only on desktop. Mobile keeps the same scrollable without a
/// persistent track.
class MagicDesktopScrollbar extends StatefulWidget {
  const MagicDesktopScrollbar({
    required this.axis,
    required this.builder,
    this.controller,
    super.key,
  });

  final Axis axis;
  final MagicScrollableBuilder builder;
  final ScrollController? controller;

  @override
  State<MagicDesktopScrollbar> createState() => _MagicDesktopScrollbarState();
}

class _MagicDesktopScrollbarState extends State<MagicDesktopScrollbar> {
  late ScrollController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _setController(widget.controller);
  }

  @override
  void didUpdateWidget(MagicDesktopScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    if (_ownsController) _controller.dispose();
    _setController(widget.controller);
  }

  void _setController(ScrollController? supplied) {
    _ownsController = supplied == null;
    _controller = supplied ?? ScrollController();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This widget owns its explicit scrollbar; suppress the app-level one for
    // the nested Scrollable so a desktop user never sees two thumbs.
    final child = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: widget.builder(context, _controller),
    );
    if (!_usesDesktopPointer(context)) return child;
    return Scrollbar(
      key: ValueKey('magic-desktop-scrollbar-${widget.axis.name}'),
      controller: _controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      scrollbarOrientation: widget.axis == Axis.vertical
          ? ScrollbarOrientation.right
          : ScrollbarOrientation.bottom,
      child: child,
    );
  }

  bool _usesDesktopPointer(BuildContext context) {
    return switch (Theme.of(context).platform) {
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.macOS => true,
      _ => kIsWeb && MediaQuery.sizeOf(context).width >= 840,
    };
  }
}
