import 'package:flutter/widgets.dart';

/// An [IndexedStack] that mounts each page only on its first visit, then keeps
/// that element alive at the same index. This avoids an eager API/bootstrap
/// burst while preserving sockets, scroll positions and form state on return.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late final Set<int> _mountedIndexes = {widget.index};

  @override
  void didUpdateWidget(covariant LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _mountedIndexes.removeWhere((index) => index >= widget.children.length);
    _mountedIndexes.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.index >= 0 && widget.index < widget.children.length);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          if (_mountedIndexes.contains(i))
            widget.children[i]
          else
            const SizedBox.shrink(),
      ],
    );
  }
}
