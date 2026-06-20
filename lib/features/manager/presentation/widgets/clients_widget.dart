import 'package:flutter/material.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/leads_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_widget.dart';

/// Hosts the «Лиды» and «Ученики» boards behind a [SegmentedButton] toggle.
///
/// Both children are kept alive inside an [IndexedStack] so kanban scroll
/// positions and [LeadsWidget]'s loaded-more state survive a segment switch.
class ClientsWidget extends StatefulWidget {
  const ClientsWidget({super.key});

  @override
  State<ClientsWidget> createState() => _ClientsWidgetState();
}

class _ClientsWidgetState extends State<ClientsWidget> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.people_outline_rounded),
                  label: Text('Лиды'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.school_outlined),
                  label: Text('Ученики'),
                ),
              ],
              selected: {_segment},
              onSelectionChanged: (s) => setState(() => _segment = s.first),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _segment,
            children: const [LeadsWidget(), StudentsBoardWidget()],
          ),
        ),
      ],
    );
  }
}
