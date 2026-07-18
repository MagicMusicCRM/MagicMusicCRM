import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/lazy_indexed_stack.dart';

void main() {
  testWidgets('mounts pages lazily and preserves already visited pages', (
    tester,
  ) async {
    final mounts = [0, 0, 0];

    Widget host(int index) => MaterialApp(
      home: LazyIndexedStack(
        index: index,
        children: [for (var i = 0; i < 3; i++) _Probe(i, mounts)],
      ),
    );

    await tester.pumpWidget(host(0));
    expect(mounts, [1, 0, 0]);

    await tester.pumpWidget(host(2));
    expect(mounts, [1, 0, 1]);

    await tester.pumpWidget(host(0));
    expect(mounts, [1, 0, 1]);

    await tester.pumpWidget(host(1));
    expect(mounts, [1, 1, 1]);
  });
}

class _Probe extends StatefulWidget {
  const _Probe(this.index, this.mounts);

  final int index;
  final List<int> mounts;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.mounts[widget.index]++;
  }

  @override
  Widget build(BuildContext context) => Text('page ${widget.index}');
}
