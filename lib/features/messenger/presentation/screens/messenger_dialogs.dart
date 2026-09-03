import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// «Информация об ответе» dialog for an administration group request: who
/// responded first and when. Extracted from _MessengerScreenState — pure
/// (reads only the passed item + context).
void showStatusInfoDialog(BuildContext context, Map<String, dynamic> item) {
  final groupData = item['_group_data'];
  if (groupData == null) return;

  final respondedAt = groupData['responded_at'];
  if (respondedAt == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('На этот запрос еще никто не ответил')),
    );
    return;
  }

  final responder = groupData['first_responder'];
  final responderName = responder != null
      ? '${responder['first_name'] ?? ''} ${responder['last_name'] ?? ''}'
            .trim()
      : 'Неизвестно';

  final time = DateFormat('dd.MM HH:mm').format(DateTime.parse(respondedAt));

  showMagicDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Информация об ответе'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.person_rounded, color: AppColor.gold),
            title: const Text('Ответил первым:'),
            subtitle: Text(responderName),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            leading: const Icon(
              Icons.access_time_rounded,
              color: AppColor.gold,
            ),
            title: const Text('Время ответа:'),
            subtitle: Text(time),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}
