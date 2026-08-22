import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

class SharedTaskMetaChip extends StatelessWidget {
  const SharedTaskMetaChip({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: AppColor.goldSoft,
      borderRadius: BorderRadius.circular(AppRadius.chip),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColor.gold),
        const SizedBox(width: 5),
        Text(label),
      ],
    ),
  );
}

String sharedTaskPriorityLabel(Object? value) => switch (value?.toString()) {
  'high' => 'Высокий',
  'low' => 'Низкий',
  _ => 'Обычный',
};
