import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_models.dart';

Future<TeacherStatsRateChange?> showTeacherStatsRateDialog({
  required BuildContext context,
  required String title,
  required String description,
  required List<String> lessonIds,
  num? initialRate,
}) {
  return showDialog<TeacherStatsRateChange>(
    context: context,
    builder: (_) => _TeacherStatsRateDialog(
      title: title,
      description: description,
      lessonIds: lessonIds,
      initialRate: initialRate,
    ),
  );
}

Future<TeacherStatsGroupRateChange?> showTeacherStatsGroupRateDialog({
  required BuildContext context,
  required String groupName,
  required num? currentRate,
}) {
  return showDialog<TeacherStatsGroupRateChange>(
    context: context,
    builder: (_) => _TeacherStatsGroupRateDialog(
      groupName: groupName,
      currentRate: currentRate,
    ),
  );
}

class _TeacherStatsRateDialog extends StatefulWidget {
  const _TeacherStatsRateDialog({
    required this.title,
    required this.description,
    required this.lessonIds,
    this.initialRate,
  });

  final String title;
  final String description;
  final List<String> lessonIds;
  final num? initialRate;

  @override
  State<_TeacherStatsRateDialog> createState() =>
      _TeacherStatsRateDialogState();
}

class _TeacherStatsRateDialogState extends State<_TeacherStatsRateDialog> {
  final TextEditingController _reasonController = TextEditingController();
  num? _rate;
  bool _touched = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.description,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 12),
          TeacherRateSelector(
            initialRate: widget.initialRate,
            allowInherit: true,
            onChanged: (value) => setState(() {
              _rate = value;
              _touched = true;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            maxLength: 500,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Причина изменения *'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _touched
              ? () {
                  final reason = _reasonController.text.trim();
                  if (reason.isEmpty) return;
                  Navigator.pop(
                    context,
                    TeacherStatsRateChange(
                      lessonIds: List.unmodifiable(widget.lessonIds),
                      teacherRate: _rate,
                      reasonText: reason,
                    ),
                  );
                }
              : null,
          child: const Text('Применить'),
        ),
      ],
    );
  }
}

class _TeacherStatsGroupRateDialog extends StatefulWidget {
  const _TeacherStatsGroupRateDialog({
    required this.groupName,
    required this.currentRate,
  });

  final String groupName;
  final num? currentRate;

  @override
  State<_TeacherStatsGroupRateDialog> createState() =>
      _TeacherStatsGroupRateDialogState();
}

class _TeacherStatsGroupRateDialogState
    extends State<_TeacherStatsGroupRateDialog> {
  late num? _rate = widget.currentRate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.groupName),
      content: SizedBox(
        width: 360,
        child: TeacherRateSelector(
          initialRate: widget.currentRate,
          allowInherit: true,
          label: 'Ставка по данной группе',
          onChanged: (rate) => _rate = rate,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, TeacherStatsGroupRateChange(_rate)),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
